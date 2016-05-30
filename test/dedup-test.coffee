uuid = require 'uuid'
path = require 'path'
Promise = require 'bluebird'
{
  writeFileAsync,
  readdirAsync,
  unlinkAsync,
  mkdirAsync,
  statAsync,
  rmdirAsync
} = Promise.promisifyAll require 'fs'
{spawn} = require 'child_process'
{expect} = require 'chai'
assert = require 'assert'


TEST_DIR_PATH = 'test/temp'

getTempPath = -> path.join TEST_DIR_PATH, uuid.v4()

generateFileAsync = (length)->
  buffer = new Buffer length
  i = 0
  while i < length
    fourBytes = Math.random() * 0xFFFFFFFF
    for j in [0...4]
      buffer[i+j] = fourBytes & 0xFF
      fourBytes = fourBytes >> 8
    i+=4
  filePath = getTempPath()
  writeFileAsync filePath, buffer
    .then -> [filePath, buffer]

duplicateFileAsync = (buffer)->
  filePath = getTempPath()
  writeFileAsync filePath, buffer
    .then -> [filePath, buffer]

callDedup = (directory, {fast, recursive})->
  paramList = ['dedup.js', TEST_DIR_PATH]

  paramList.push '--fast' if fast
  paramList.push '--recursive' if recursive
  new Promise (resolve, reject)->
    proc = spawn 'node', paramList
    duplicates = []
    errors = []
    proc.stdout.on 'data', (duplicate)->
      duplicates.push duplicate.toString()
    proc.stderr.on 'data', (error)->
      errors.push error.toString()
    proc.on 'close', ->
      return reject errors if errors.length
      resolve duplicates

BIG_FILE_SIZE = 1000000
SMALL_FILE_SIZE = 100

describe 'dedup', ->
  before ->
    statAsync TEST_DIR_PATH
      .catch -> mkdirAsync TEST_DIR_PATH

  after ->
    cleanDir TEST_DIR_PATH
      .then -> rmdirAsync TEST_DIR_PATH

  cleanDir = (dir)->
    readdirAsync dir
      .then (files)->
        Promise.all files.map (file)->
          unlinkAsync path.join TEST_DIR_PATH, file

  testScenario = (fileSize, params)->
    beforeEach ->
      cleanDir TEST_DIR_PATH

    it 'should return a duplicate when two files are the same', ->
      dups = []
      generateFileAsync fileSize
        .then ([filePath, buffer])->
          duplicateFileAsync buffer
        .then ([filePath])->
          callDedup TEST_DIR_PATH, params
        .then (duplicates)->
          duplicates = duplicates.map (d)-> d.toString()
          expect(duplicates.length).to.equal 1

    it 'should return two duplicates when three files are the same', ->
      generateFileAsync fileSize
        .spread (filePath, buffer)->
          Promise.all [
            duplicateFileAsync buffer
            duplicateFileAsync buffer
          ]
        .then ->
          callDedup TEST_DIR_PATH, params
        .then (duplicates)->
          expect(duplicates.length).to.equal 2

    it 'should return no duplicates when all files are unique', ->
      Promise.all [
        generateFileAsync fileSize
        generateFileAsync fileSize
        generateFileAsync fileSize
        generateFileAsync fileSize
      ]
        .then ->
          callDedup TEST_DIR_PATH, params
        .then (duplicates)->
          expect(duplicates.length).to.equal 0

  describe 'comparing small files', ->
    testScenario SMALL_FILE_SIZE, {}

  describe 'comparing large files', ->
    describe 'with fast compare', ->
      testScenario BIG_FILE_SIZE, {fast: true}
    describe 'with full hashing', ->
      testScenario BIG_FILE_SIZE, {fast: false}
