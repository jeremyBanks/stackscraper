what-i-want:
	# compile user script
	coffee --bare --compile stackscraper.user.coffee
	
	# grab chrome extension manfiest data from script and put it in manifest.json
	coffee -e "require('util').puts JSON.stringify require('stackscraper.user').manifest" > manifest.json
	
	# create ZIP for app store 
	rm for-chrome-web-store.zip; true
	zip for-chrome-web-store.zip manifest.json stackscraper.user.js stackscraper.user.coffee icon128.png
	
	# install in Chrome
	open -a /Applications/Google\ Chrome.app stackscraper.user.js 
