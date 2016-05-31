#dedup

##Installation
```bash
npm install -g node-dupliccation-finder
```

##Usage
```bash
dedup <options> <directory> <directory>...
```

##Example
lists duplicate mp3 files recursively except for Lil Dicky's directory
```bash
dedup --ignore Jay-Z/ --only mp3 -r myMusic other/myFriendsMusic
```


delete duplicates
```bash
dedup --delete someNestedDirs other/NestedDirs
```

##Future
- more documentation
- make exportable as module
- yes/no dialog before deleting
- separate dev dependencies
