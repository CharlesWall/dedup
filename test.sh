NODE_PATH=. mocha --compilers coffee:coffee-script/register -R spec --timeout 10000 $@
