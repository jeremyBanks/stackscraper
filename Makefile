all:
	coffee --print --bare --compile scrape.user.coffee | pbcopy
