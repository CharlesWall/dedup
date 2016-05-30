#!/usr/bin/env node#

Promise = require 'bluebird'
startTime = Date.now()
{
  readdirAsync,
  readFileAsync,
  statAsync,
  unlinkAsync,
  createReadStream
} = Promise.promisifyAll require 'fs'
crypto = require 'crypto'
path = require 'path'
Queue = require 'promise-queue'

parameters = Array::slice.call process.argv, 2
fileQueue = new Queue 10

recursive = false
removeDuplicate = false
ignoreList = {}
verbose = false
veryverbose = false
fast = false
searchDirs = []
unsafe = false
duplicates = []
only = []

FAST_READ_BUFFER_SIZE = 10000

i = 0
while i < parameters.length
  parameter = parameters[i]

  switch parameter
    when '-r', '--recursive'
      recursive = true
    when '--delete'
      removeDuplicate = true
    when '-i', '--ignore'
      ignore = parameters[++i]
      ignoreList[ignore] = true
    when '-v', '--verbose'
      verbose = true
    when '-f', '--fast'
      fast = true
    when '--logging'
      veryverbose = true
    when '--unsafe'
      unsafe = true
    when '--only'
      only ?= []
      only.push parameters[++i]
    else
      searchDirs.push parameter
  i++

fileHashes = {}

if fast and removeDuplicate and not unsafe
  console.log 'bailing because you are trying to run fast and remove duplicates'
  console.log 'without setting --unsafe flag'
  process.exit 1


console.log {recursive, removeDuplicate, ignoreList, verbose, searchDirs} if veryverbose

readFileFastAsync = (filePath)->
  fileData = new Buffer(FAST_READ_BUFFER_SIZE)
  datas = []
  bytesRead = 0
  new Promise (resolve, reject)->
    readStream = createReadStream filePath
    readStream.on 'data', (data)->
      bytesRead += data.length
      datas.push data
      if (bytesRead >= FAST_READ_BUFFER_SIZE)
        readStream.close()
        resolve fileData
    readStream.on 'end', resolve
    readStream.on 'error', reject
  .then -> Buffer.concat(datas).slice 0, FAST_READ_BUFFER_SIZE

outputDuplicate = (duplicates)->
  if verbose
    console.log duplicates...
  else
    console.log duplicates[duplicates.length - 1]

scanDir = (dir)->
  scanSubpath = (file)->
    filePath = path.join dir, file
    statAsync filePath
      .then (stats)->
        if ignoreList[filePath]
          return
        else if stats.isDirectory()
          scanDir filePath if recursive
        else
          scanFile filePath

  readdirAsync dir
    .then (files)-> Promise.all files.map scanSubpath

scanFile = (filePath)->
  if only?.length
    match = only.find (suffix)-> filePath.endsWith suffix
    return unless match

  fileQueue.add(->
    if fast
      console.log "fast read #{filePath}" if veryverbose
      readFileFastAsync filePath
    else
      console.log "full read #{filePath}" if veryverbose
      readFileAsync filePath
  ).then (fileContents) -> storeHash fileContents, filePath

storeHash = (fileContents, filePath)->
  hash = crypto.createHash('md5')
    .update(fileContents)
    .digest('hex')
  existing = fileHashes[hash] || []
  existing.push filePath
  fileHashes[hash] = existing
  if existing.length > 1
    duplicates.push filePath
    outputDuplicate existing
    if removeDuplicate
      fileQueue.add -> unlinkAsync filePath

Promise.all searchDirs.map scanDir
  .then ->
    if veryverbose
      console.log "#{(Date.now() - startTime)/1000} seconds"
      console.log "#{duplicates.length} duplicates"
      console.log duplicates