module App (runApp, dummyFun) where

runApp :: IO ()
runApp = putStrLn "Hello"

dummyFun :: Int
dummyFun = if limit > 100 then 0 else 42
  where
    limit = 7 :: Int
