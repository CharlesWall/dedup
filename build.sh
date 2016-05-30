stat dedup && rm dedup.js
echo '#!/usr/bin/env node' > dedup.js
coffee -p --no-header -c src/dedup.coffee >> dedup.js && echo 'success'
