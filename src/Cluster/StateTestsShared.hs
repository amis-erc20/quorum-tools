{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts  #-}
-- Utilities shared between the public and private state tests
module Cluster.StateTestsShared where

import           Control.Monad.Except       (MonadError(..))
import           Control.Monad.Managed      (MonadManaged)
import qualified Data.Map                   as Map

import Prelude hiding (FilePath)
import Turtle
import qualified Cluster.Client as Client
import Cluster.Control
import Cluster.Types
import Cluster.Util (bytes32P, toInt, HexPrefix(..), printHex, intToBytes32)
import TestOutline hiding (verify)

expectEq :: MonadError FailureReason m => Either Text Int -> Int -> m ()
expectEq val expected = when (val /= Right expected) $
  throwError $ WrongValue expected val

createContract :: MonadManaged m => Geth -> Contract -> Behavior TxAddrs -> m Addr
createContract geth contract addrs = do
  let initVal = intToBytes32 42
  creationTxEvt <- watch addrs $ \(TxAddrs addrMap) ->
    if not (Map.null addrMap)
    then Just (head (Map.elems addrMap))
    else Nothing
  Client.create geth (CreateArgs contract initVal Sync)

  wait creationTxEvt

incrementStorage :: MonadIO io => Geth -> Contract -> Addr -> io ()
incrementStorage geth (Contract privacy _ _ _) (Addr addrBytes) =
  -- TODO: remove "increment()" duplication
  Client.sendTransaction geth (Tx (Just addrBytes) "increment()" privacy Sync)

getStorage :: MonadIO io => Geth -> Contract -> Addr -> io (Either Text Int)
getStorage geth _contract addr = do
  resp <- Client.call geth (CallArgs (unAddr addr) "get()")
  pure $ case resp of
    Left msg -> Left msg
    -- we get this back when not party to a transaction. bug?
    Right "0x" -> Right 0
    Right resp' -> case match (bytes32P WithPrefix) resp' of
      [b32] -> case toInt b32 of
        Nothing -> Left ("couldn't coerce to int: " <> printHex WithPrefix b32)
        Just result -> Right result
      _ -> Left ("failed to find hex string: " <> resp')

-- pragma solidity ^0.4.0;
--
-- contract SimpleStorage {
--     uint storedData;
--
--     function SimpleStorage(uint initVal) {
--         storedData = initVal;
--     }
--
--     function increment() {
--         storedData = storedData + 1;
--     }
--
--     function get() constant returns (uint) {
--         return storedData;
--     }
-- }

simpleStorage :: Privacy -> Contract
simpleStorage privacy = Contract
  privacy
  ["increment()", "get()"]
  "6060604052341561000c57fe5b6040516020806100fd833981016040528080519060200190919050505b806000819055505b505b60bc806100416000396000f30060606040526000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff1680636d4ce63c146044578063d09de08a146067575bfe5b3415604b57fe5b60516076565b6040518082815260200191505060405180910390f35b3415606e57fe5b60746081565b005b600060005490505b90565b6001600054016000819055505b5600a165627a7a72305820ce68eb4fb5f27717950dfc3d9e95e23c6ba3815af890ad8705a3a68af19c1ac20029"
  "[{\"constant\":true,\"inputs\":[],\"name\":\"get\",\"outputs\":[{\"name\":\"\",\"type\":\"uint256\"}],\"payable\":false,\"type\":\"function\"},{\"constant\":false,\"inputs\":[],\"name\":\"increment\",\"outputs\":[],\"payable\":false,\"type\":\"function\"},{\"inputs\":[{\"name\":\"initVal\",\"type\":\"uint256\"}],\"payable\":false,\"type\":\"constructor\"}]"
