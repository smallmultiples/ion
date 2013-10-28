core = require './core'
Operation = require './reactive/Operation'

assignAddIndexes = (node, depthStack = [0]) ->
    if node?.op?
        operation = Operation.getOperation node.op
        if operation.addIndex
            index = depthStack[depthStack.length - 1]++
            # push this index value into the operation args
            node.args.push index
        if operation.newOutputContext
            depthStack.push [0]
        if node?.args?
            for child in node.args when child?
                assignAddIndexes child, depthStack
        if operation.newOutputContext
            depthStack.pop()
    return

exports.postprocess = postprocess = (ast) ->
    assignAddIndexes ast
    return ast