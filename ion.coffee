
class Token
	constructor: (@symbol, @type, @text = @type, @value) ->
	toJSON: -> if @symbol then @type else @value
	toString: -> @text

tokentypes = [
	[/^\s*#.*/, (x) -> null]
	[/^\s*\[/, (x) -> new Token true, '[', x]
	[/^\s*\]/, (x) -> new Token true, ']', x]
	[/^\s*:/,  (x) -> new Token true, ':', x]
	[/^\s*,/,  (x) -> new Token true, ',', x]
	[/^\s*"([^"\\]|(\\([\/'"\\bfnrt]|(u[a-fA-F0-9]{4}))))*"/, (x) -> new Token false, 'quoted', x, JSON.parse x]
	[/^[^,:\[\]#]+/, (x) -> new Token false, 'unquoted', x, x.trim()]
]

parseTokens = (line) ->
	if line.trim().length is 0
		return null
	tokens = []
	while line.trim().length > 0
		matched = false
		for tokentype in tokentypes
			match = line.match tokentype[0]
			if match?
				matched = true
				#	parse and add the token to our list
				token = tokentype[1] text = match[0]
				tokens.push token if token?
				#	consume the matched token
				line = line.substring text.length
				break
		if not matched
			# this shouldn't ever happen
			throw new Error line
	return tokens

min = (a, b) ->
	return a unless b?
	return b unless a?
	return a if a <= b
	return b

class Node
	constructor: (@line, @lineNumber, @indent) ->
		if line?
			@tokens = parseTokens line
			@isText = isText @tokens
			if @tokens?.length >= 2 and not (key = @tokens[0]).symbol and @tokens[1].type is ':'
				@key = key.value
			@hasColon = @key? or @tokens?[0]?.type is ':'
	error: (message, lineNumber) ->
		error = new Error "#{message}, line:#{@lineNumber}"
		error.lineNumber = @lineNumber
		error.line = @line
		error
	getSmallestDescendantIndent: ->
		smallest = null
		if @children?
			for child in @children
				smallest = min smallest, child.indent
				smallest = min smallest, child.getSmallestDescendantIndent()
		smallest
	getAllDescendantLines: (lines = [], indent) ->
		indent ?= @getSmallestDescendantIndent()
		if @children?
			for child in @children
				lines.push child.line.substring indent
				child.getAllDescendantLines lines, indent
		return lines
	getComplexType: (options) ->
		#	see if we have an explicit type
		explicitType = if @tokens?.length >= 3 then @tokens?.slice(2).join('').trim()
		if explicitType?
			options.explicit = true
			return explicitType
		nonEmptyChildCount = 0
		keyCount = 0
		keys = {}
		duplicateKeys = false
		for child in @children
			if (child.isText and not child.key) or (child.children? and not child.hasColon)
				return '""'
			if child.tokens
				nonEmptyChildCount++
				if child.key
					keyCount++
					if keys[child.key]
						duplicateKeys = true
					keys[child.key] = true
		if duplicateKeys or nonEmptyChildCount > 0 and keyCount is 0
			return '[]'
		if keyCount is nonEmptyChildCount
			return '{}'
		throw @error 'Inconsistent child keyCount'
	getSimpleValue: (options) ->
		tokens = @tokens
		return undefined if tokens.length is 0
		if @key
			tokens = tokens.slice 2
		else if @hasColon
			tokens = tokens.slice 1
		#	empty is implied null
		if tokens.length is 0
			return null
		#	expicit array
		return value if tokens.length >= 2 and tokens[0].type is '[' and tokens[tokens.length - 1].type is ']' and value = getArray tokens.slice 1, -1
		if not @isText
			#	single value
			if tokens.length is 1
				token = tokens[0]
				if token.type is 'quoted'
					options.explicit = true
				return token.value
			#	implicit array
			return value if value = getArray tokens
		#	string
		return tokens.join('').trim()
	doChildrenHaveKeys: ->
		for child in @children when child.key?
			return true
		return false
	getComplexValue: (options) ->
		type = @getComplexType options
		if type is '""'
			value = @getAllDescendantLines().join '\n'
		else if type is '[]'
			# if the children have keys, then this is a different animal
			if @doChildrenHaveKeys()
				value = []
				current = null
				#	read in the objects skipping to the next one whenever we have a new key
				for child in @children when child.tokens
					key = child.key
					if current == null or current.hasOwnProperty key
						value.push current = {}
					current[key] = child.getValue()
			else
				value = (child.getValue() for child in @children when child.tokens)
		else
			value = {}
			for child in @children when child.tokens
				value[child.key] = child.getValue()
		return value
	getValue: ->
		options = {}
		if @children?
			if not @hasColon and @isText
				throw @children[0].error 'Children not expected'
			value = @getComplexValue options
		else
			value = @getSimpleValue options

		if typeof value is 'string' and not options.explicit
			value = processUnquoted value

		return value

processUnquoted = (text) ->
	for processor in ion.processors
		result = processor text
		if result isnt undefined
			return result
	return text

isText = (tokens) ->
	if tokens
		punctuation = /[^-\s\w]/
		for token in tokens
			if token.type is 'unquoted'
				value = token.value
				if typeof value is 'string' and punctuation.test value
					return true
	return false

#	returns an array of items if they are all comma separated, otherwise null
getArray = (tokens) ->
	for token, index in tokens
		if index % 2 is 0
			if token.symbol
				return null
		else
			if token.type isnt ','
				return null
	return (item.value for item in tokens by 2)

nest = (nodes) ->
	root = new Node(null, null, -1)
	stack = [root]
	for node in nodes
		while node.indent <= (parent = stack[stack.length-1]).indent
			stack.pop()
		(parent.children ?= []).push node
		stack.push node
	root

# stringify variables
obj_delim = ['','']
arr_delim = ['','']
sep = ''
wordwrap_len = 75

quote = (string) ->   
	#dummy function for now...
	return string

wordwrap = (str, width, brk, cut) ->
	brk = brk or "\n"
	width = width or 75
	cut = cut or false
	return str  unless str
	regex = ".{1," + width + "}(\\s|$)" + ((if cut then "|.{" + width + "}|.+$" else "|\\S+?(\\s|$)"))
	str.match(RegExp(regex, "g")).map((s)->s.replace(/\n$/,'')).join(brk)

str = (key, holder,first_run=false,gap=0,indent,replacer) ->    
	# Produce a string from holder[key].
	i = undefined # The loop counter.
	k = undefined
	v = undefined
	length = undefined
	# The member key.
	# The member value.
	mind = gap
	partial = undefined
	value = holder[key]

	# If the value has a toJSON method, call it to obtain a replacement value.
		
	# If we were called with a replacer function, then call the replacer to
	# obtain a replacement value.
	if typeof replacer is "function"
		try
			replaced = replacer.call(holder, key, value)  
			return replaced
		catch e
			# Can't replace, move on

	if not first_run
		gap += indent

	# What happens next depends on the value's type.
	switch typeof value
		when "string"
			if value.length>wordwrap_len || value.indexOf("\n") >= 0
				"\n"+gap+wordwrap(value, wordwrap_len, "\n"+gap)
			else
				value
		when "number"
			
			# JSON numbers must be finite. Encode non-finite numbers as null.
			(if isFinite(value) then String(value) else "null")
		when "boolean", "null"
			
			# If the value is a boolean or null, convert it to a string. Note:
			# typeof null does not produce 'null'. The case is included here in
			# the remote chance that this gets fixed someday.
			String value
		
		# If the type is 'object', we might be dealing with an object or an array or
		# null.
		when "object"
			
			# Due to a specification blunder in ECMAScript, typeof null is 'object',
			# so watch out for that case.
			return "null"  unless value
			
			# Make an array to hold the partial results of stringifying this object value.
			partial = []
			
			# Is the value an array?
			if Object::toString.apply(value) is "[object Array]"
				
				# The value is an array. Stringify every element. Use null as a placeholder
				# for non-JSON values.
				length = value.length
				i = 0
				while i < length
					partial[i] = str(i, value, true, '', indent, replacer) or "null"
					i += 1
				
				# Join all of the elements together, separated with commas, and wrap them in
				# brackets.
				v = (if partial.length is 0
						"[]" 
					else 
						arr_delim[0] + "\n" + partial.join(sep+"\n").replace(/^\n/,'').replace(/^/gm,gap) + mind + arr_delim[1]
					)
				gap = mind
				return v
			
			# If the replacer is an array, use it to select the members to be stringified.
			if replacer and typeof replacer is "object"
				length = replacer.length
				i = 0
				while i < length
					if typeof replacer[i] is "string"
						k = replacer[i]
						v = str(k, value, true, gap, indent, replacer)
						partial.push quote(k) + ": " + v  if v
					i += 1
			else               
				# Otherwise, iterate through all of the keys in the object.
				for k of value
					if Object::hasOwnProperty.call(value, k)
						v = str(k, value, false, '', indent, replacer)
						partial.push quote(k) + ": " + v  if v
			
			# Join all of the member texts together, separated with commas,
			# and wrap them in braces.
			v = (if partial.length is 0 
					"{}" 
				else 
					obj_delim[0] + "\n" + partial.join(sep+"\n").replace(/^\n/,'').replace(/^/gm,gap) + mind + obj_delim[1]
				)
			gap = mind
			return v

ion =
	parse: (text, options) ->
		#	trim the text
		text = text.trim()
		#	split text into lines
		nodes = []
		for line, index in text.split '\n' when line.trim()[0] isnt '#'
			indent = (if line.trim().length is 0 then indent else indent = line.match(/^\s*/)?[0]?.length) ? 0
			nodes.push new Node line, index + 1, indent
		#	nest the lines as children of a root node
		root = nest nodes
		#	now get the root value
		value = root.getValue()
		return value
	#	extensible ion processors for converting unquoted text to other values
	processors: [
		(text) -> if text.match /^\s*null\s*$/ then return null
		(text) -> 
			if text.match /^\s*(true|false|yes|no)\s*$/ 
				if (text=='true' || text=='yes') then return true
				else return false
		(text) -> if text.match /^\s*[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?\s*$/ then return Number text.trim()
		(text) -> if text.match /^\s*\d\d\d\d-\d\d-\d\d(T\d\d:\d\d(:\d\d(\.\d{1,3})?)?(Z|([+-]\d\d:\d\d))?)?\s*$/ then return new Date text.trim()
		(text) -> if text.match /^\s*{}\s*$/ then return {}
		(text) ->
			#	this attempts to match a table format and convert it to an array of objects
			#	header:     values:    separated:    space:
			lines = text.split '\n'
			if lines.length > 3
				if lines[0].match /^([^: ]+( [^: ]+)*:( +|$)){2,}$/
					headers = []
					regex = /[^: ]+( [^: ]+)*/g
					while match = regex.exec lines[0]
						headers.push [new Node(match[0]).getValue(), match.index]
					if headers.length >= 2
						array = []
						for i in [1...lines.length]
							line = lines[i]
							array.push item = {}
							for header, index in headers
								key = header[0]
								start = header[1]
								end = headers[index+1]?[1]
								cell = line.substring start, end
								if cell.trim().length
									value = new Node(cell).getValue()
									item[key] = value
						return array
			return
	]

	# This is basicaly the opposite of parse
	stringify: (value, replacer, space) ->
		
		# The stringify method takes a value and an optional replacer, and an optional
		# space parameter, and returns a JSON text. The replacer can be a function
		# that can replace values, or an array of strings that will select the keys.
		# A default replacer method can be provided. Use of the space parameter can
		# produce text that is more easily readable.
		i = undefined
		gap = ""
		indent = ""
		
		# If the space parameter is a number, make an indent string containing that
		# many spaces.
		if typeof space is "number"
			i = 0
			while i < space
				indent += " "
				i += 1
		
		# If the space parameter is a string, it will be used as the indent string.
		else indent = space  if typeof space is "string"
		
		# If there is a replacer, it must be a function or an array.
		# Otherwise, throw an error.
		throw new Error("ION.stringify replacer")  if replacer and typeof replacer isnt "function" and (typeof replacer isnt "object" or typeof replacer.length isnt "number")
		
		# Make a fake root object containing our value under the key of ''.
		# Return the result of stringifying the value.
		return str("",{"": value},true,'',indent,replacer)

if typeof module is 'undefined'
	#	global.ion
	do -> this.ion = ion
else
	#	nodejs module
	module.exports = ion

	if require.main is module
		fs = require 'fs'
		args = process.argv.slice 2
		if args.length is 0
			return console.log 'Usage: ion file.ion'
		content = fs.readFileSync args[0], 'utf8'
		object = ion.parse content
		console.log(JSON.stringify(object, null, '    '))
