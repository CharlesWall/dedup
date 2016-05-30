#!/usr/bin/env node
(function() {
  var FAST_READ_BUFFER_SIZE, Promise, Queue, createReadStream, crypto, duplicates, fast, fileHashes, fileQueue, i, ignore, ignoreList, only, outputDuplicate, parameter, parameters, path, readFileAsync, readFileFastAsync, readdirAsync, recursive, ref, removeDuplicate, scanDir, scanFile, searchDirs, startTime, statAsync, storeHash, unlinkAsync, unsafe, verbose, veryverbose;

  Promise = require('bluebird');

  startTime = Date.now();

  ref = Promise.promisifyAll(require('fs')), readdirAsync = ref.readdirAsync, readFileAsync = ref.readFileAsync, statAsync = ref.statAsync, unlinkAsync = ref.unlinkAsync, createReadStream = ref.createReadStream;

  crypto = require('crypto');

  path = require('path');

  Queue = require('promise-queue');

  parameters = Array.prototype.slice.call(process.argv, 2);

  fileQueue = new Queue(10);

  recursive = false;

  removeDuplicate = false;

  ignoreList = {};

  verbose = false;

  veryverbose = false;

  fast = false;

  searchDirs = [];

  unsafe = false;

  duplicates = [];

  only = [];

  FAST_READ_BUFFER_SIZE = 10000;

  i = 0;

  while (i < parameters.length) {
    parameter = parameters[i];
    switch (parameter) {
      case '-r':
      case '--recursive':
        recursive = true;
        break;
      case '--delete':
        removeDuplicate = true;
        break;
      case '-i':
      case '--ignore':
        ignore = parameters[++i];
        ignoreList[ignore] = true;
        break;
      case '-v':
      case '--verbose':
        verbose = true;
        break;
      case '-f':
      case '--fast':
        fast = true;
        break;
      case '--logging':
        veryverbose = true;
        break;
      case '--unsafe':
        unsafe = true;
        break;
      case '--only':
        if (only == null) {
          only = [];
        }
        only.push(parameters[++i]);
        break;
      default:
        searchDirs.push(parameter);
    }
    i++;
  }

  fileHashes = {};

  if (fast && removeDuplicate && !unsafe) {
    console.log('bailing because you are trying to run fast and remove duplicates');
    console.log('without setting --unsafe flag');
    process.exit(1);
  }

  if (veryverbose) {
    console.log({
      recursive: recursive,
      removeDuplicate: removeDuplicate,
      ignoreList: ignoreList,
      verbose: verbose,
      searchDirs: searchDirs
    });
  }

  readFileFastAsync = function(filePath) {
    var bytesRead, datas, fileData;
    fileData = new Buffer(FAST_READ_BUFFER_SIZE);
    datas = [];
    bytesRead = 0;
    return new Promise(function(resolve, reject) {
      var readStream;
      readStream = createReadStream(filePath);
      readStream.on('data', function(data) {
        bytesRead += data.length;
        datas.push(data);
        if (bytesRead >= FAST_READ_BUFFER_SIZE) {
          readStream.close();
          return resolve(fileData);
        }
      });
      readStream.on('end', resolve);
      return readStream.on('error', reject);
    }).then(function() {
      return Buffer.concat(datas).slice(0, FAST_READ_BUFFER_SIZE);
    });
  };

  outputDuplicate = function(duplicates) {
    if (verbose) {
      return console.log.apply(console, duplicates);
    } else {
      return console.log(duplicates[duplicates.length - 1]);
    }
  };

  scanDir = function(dir) {
    var scanSubpath;
    scanSubpath = function(file) {
      var filePath;
      filePath = path.join(dir, file);
      return statAsync(filePath).then(function(stats) {
        if (ignoreList[filePath]) {

        } else if (stats.isDirectory()) {
          if (recursive) {
            return scanDir(filePath);
          }
        } else {
          return scanFile(filePath);
        }
      });
    };
    return readdirAsync(dir).then(function(files) {
      return Promise.all(files.map(scanSubpath));
    });
  };

  scanFile = function(filePath) {
    var match;
    if (only != null ? only.length : void 0) {
      match = only.find(function(suffix) {
        return filePath.endsWith(suffix);
      });
      if (!match) {
        return;
      }
    }
    return fileQueue.add(function() {
      if (fast) {
        if (veryverbose) {
          console.log("fast read " + filePath);
        }
        return readFileFastAsync(filePath);
      } else {
        if (veryverbose) {
          console.log("full read " + filePath);
        }
        return readFileAsync(filePath);
      }
    }).then(function(fileContents) {
      return storeHash(fileContents, filePath);
    });
  };

  storeHash = function(fileContents, filePath) {
    var existing, hash;
    hash = crypto.createHash('md5').update(fileContents).digest('hex');
    existing = fileHashes[hash] || [];
    existing.push(filePath);
    fileHashes[hash] = existing;
    if (existing.length > 1) {
      duplicates.push(filePath);
      outputDuplicate(existing);
      if (removeDuplicate) {
        return fileQueue.add(function() {
          return unlinkAsync(filePath);
        });
      }
    }
  };

  Promise.all(searchDirs.map(scanDir)).then(function() {
    if (veryverbose) {
      console.log(((Date.now() - startTime) / 1000) + " seconds");
      console.log(duplicates.length + " duplicates");
      return console.log(duplicates);
    }
  });

}).call(this);
