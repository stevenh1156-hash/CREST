# Y.65 v5 verification
Status: deployed, awaiting Bannerlord restart + battle.
v5 logs every candidate's full param type. Next runtime.log tells us
the actual shape (array, byref, generic, etc.). If structures-found
still = 0, read the candidate logs and ship v6 to handle the shape.
