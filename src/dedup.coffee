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

logHelp = ->
  console.log 'dedup <options> <directories>'
  console.log '  -r, --recursive     search in directories recursively'
  console.log '  -d, --delete        delete duplicates when found'
  console.log '  -i, --ignore <path> ignore directories or files by relative path'
  console.log '  -v, --verbose       log both duplicate files not just the first'
  console.log '      --logging       developer output shows recursion and scanning'
  console.log '  -f, --fast          build had from first 10kb of files for faster'
  console.log '                      performance however hash conditions are possible'
  console.log '      --unsafe        must be set when deleting files base on fast'
  console.log '                      hash'
  console.log '      --only <suffix> only find duplicates with files matching the'
  console.log '                      suffix'
  console.log '  -h, --help          show this message'

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
    when '-h', '--help'
      logHelp()
      process.exit 0
    else
      searchDirs.push parameter
  i++

fileHashes = {}

if fast and removeDuplicate and not unsafe
  console.log 'bailing because you are trying to run fast and remove duplicates'
  console.log 'without setting --unsafe flag'
  process.exit 1


console.log {recursive, removeDuplicate, ignoreList, verbose, searchDirs} if veryverbose

hashFileAsync = (filePath, maxBytes)->
  new Promise (resolve, reject)->
    hash = crypto.createHash('md5')
    finish = ->
      readStream.close()
      resolve hash.digest 'hex'

    readStream = createReadStream filePath
    bytesRead = 0
    readStream.on 'data', (data)->
      if maxBytes and (bytesRead + data.length) > maxBytes
        hash.update data.slice 0, maxBytes - bytesRead
        finish()
      else
        bytesRead += data.length
        hash.update(data)
    readStream.on 'end', finish
    readStream.on 'error', reject

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
      hashFileAsync filePath, if fast then FAST_READ_BUFFER_SIZE
  ).then (hash) -> storeHash hash, filePath

storeHash = (hash, filePath)->
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
