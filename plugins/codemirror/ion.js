CodeMirror.defineMode("ion", function() {

    var cons = ['true', 'false', 'on', 'off', 'yes', 'no','null'];
    var keywordRegex = new RegExp("\\b(("+cons.join(")|(")+"))\\s*", 'i');

    return {
        token: function(stream, state) {
            var ch = stream.peek();
            if (stream.sol()) {
                state.keyFound = false;
                state.pairStart = false;
            }
            /* comments */
            if (ch == "#" && (stream.pos == 0 || /\s/.test(stream.string.charAt(stream.pos - 1)))) {
                stream.skipToEnd(); return "comment";
            }
            if (stream.sol() && stream.string.match(/:(\s+|$)/)) {
                /* Looks like a key... */
                state.keyFound = true;
                stream.skipTo(':');
                return 'atom';
            }
            if (state.keyFound && stream.match(/^:\s*/)) {
                return 'meta';
            }
            if (stream.match(/^(\{|\}|\[|\])/)) {
                if (ch == '{')
                    state.inlinePairs++;
                else if (ch == '}')
                    state.inlinePairs--;
                else if (ch == '[')
                    state.inlineList++;
                else
                    state.inlineList--;
                state.pairStart = false;
                return 'meta';
            }
            // /* start of value of a pair */
            if (state.keyFound && !state.valueStart) {
                state.valueStart = true;
             }
            if (state.valueStart) {
                expectedEnd = false
                if (state.inlinePairs) expectedEnd = '}'
                else if (state.inlineList) expectedEnd = ']'

                if (stream.match(keywordRegex)
                    && (!stream.peek() || stream.peek()=='#' || (expectedEnd && stream.peek()==expectedEnd))) 
                    { 
                        (expectedEnd && stream.skipTo(expectedEnd)) || stream.skipTo('#') || stream.skipToEnd()
                        return 'keyword';
                    }
                /* numbers */
                else if (stream.match(/^\s*-?[0-9\.\,]+\s*/) 
                    && (!stream.peek() || stream.peek()=='#' || (expectedEnd && stream.peek()==expectedEnd)))
                    { 
                        (expectedEnd && stream.skipTo(expectedEnd)) || stream.skipTo('#') || stream.skipToEnd()
                        return 'number';
                    }
                /* dates */
                else if (stream.match(/^\s*-?[0-9\-t:]+\s*/i) 
                    && (!stream.peek() || stream.peek()=='#' || (expectedEnd && stream.peek()==expectedEnd))) 
                    { 
                        (expectedEnd && stream.skipTo(expectedEnd)) || stream.skipTo('#') || stream.skipToEnd()
                        return 'variable-2';
                    }
                else {
                    (expectedEnd && stream.skipTo(expectedEnd)) || stream.skipTo('#') || stream.skipToEnd()
                    return 'string';
                }
            }
            stream.next();
            return null;
        },
        startState: function() {
            return {
                    keyFound: false,
                    inlinePairs: 0,
                    inlineList: 0
            };
        }
    };
});

CodeMirror.defineMIME("text/x-ion", "ion");
