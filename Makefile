all:
	coffee --bare --compile stackscraper.user.coffee
	coffee -e "require('util').puts JSON.stringify require('stackscraper.user').manifest" > manifest.json
	rm for-chrome-web-store.zip; true
	zip for-chrome-web-store.zip manifest.json stackscraper.user.js stackscraper.user.coffee icon128.png
