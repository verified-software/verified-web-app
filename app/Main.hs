module Main (main) where
import Server (runServer)
import System.Environment (getArgs)
import System.Exit (die)
import Text.Read (readMaybe)
main :: IO ()
main = do
  args <- getArgs
  case args of
    [] -> runServer 18080
    [port] | Just n <- readMaybe port, n > 0, n < 65536 -> runServer n
    _ -> die "Usage: verified-forum [PORT]"
