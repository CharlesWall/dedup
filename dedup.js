#!/usr/bin/env node
(function() {
  var FAST_READ_BUFFER_SIZE, Promise, Queue, createReadStream, crypto, duplicates, fast, fileHashes, fileQueue, hashFileAsync, i, ignore, ignoreList, logHelp, only, outputDuplicate, parameter, parameters, path, readFileAsync, readdirAsync, recursive, ref, removeDuplicate, scanDir, scanFile, searchDirs, searches, startTime, statAsync, storeHash, unlinkAsync, unsafe, verbose, veryverbose;

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

  logHelp = function() {
    console.log('dedup <options> <directories>');
    console.log('  -r, --recursive     search in directories recursively');
    console.log('  -d, --delete        delete duplicates when found');
    console.log('  -i, --ignore <path> ignore directories or files by relative path');
    console.log('  -v, --verbose       log both duplicate files not just the first');
    console.log('      --logging       developer output shows recursion and scanning');
    console.log('  -f, --fast          build had from first 10kb of files for faster');
    console.log('                      performance however hash conditions are possible');
    console.log('      --unsafe        must be set when deleting files base on fast');
    console.log('                      hash');
    console.log('      --only <suffix> only find duplicates with files matching the');
    console.log('                      suffix');
    return console.log('  -h, --help          show this message');
  };

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
      case '-h':
      case '--help':
        logHelp();
        process.exit(0);
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

  hashFileAsync = function(filePath, maxBytes) {
    return new Promise(function(resolve, reject) {
      var bytesRead, finish, hash, readStream;
      hash = crypto.createHash('md5');
      finish = function() {
        readStream.close();
        return resolve(hash.digest('hex'));
      };
      readStream = createReadStream(filePath);
      bytesRead = 0;
      readStream.on('data', function(data) {
        if (maxBytes && (bytesRead + data.length) > maxBytes) {
          hash.update(data.slice(0, maxBytes - bytesRead));
          return finish();
        } else {
          bytesRead += data.length;
          return hash.update(data);
        }
      });
      readStream.on('end', finish);
      return readStream.on('error', reject);
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
      return hashFileAsync(filePath, fast ? FAST_READ_BUFFER_SIZE : void 0);
    }).then(function(hash) {
      return storeHash(hash, filePath);
    });
  };

  storeHash = function(hash, filePath) {
    var existing;
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

  searches = Promise.resolve();

  searchDirs.forEach(function(dir) {
    return searches = searches.then(function() {
      return scanDir(dir);
    });
  });

  searches.then(function() {
    if (veryverbose) {
      console.log(((Date.now() - startTime) / 1000) + " seconds");
      console.log(duplicates.length + " duplicates");
      return console.log(duplicates);
    }
  });

}).call(this);
