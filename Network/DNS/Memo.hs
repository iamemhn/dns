module Network.DNS.Memo where

import Control.Applicative ((<$>))
import qualified Control.Reaper as R
import Data.ByteString.Short (ShortByteString)
import Data.List (foldl')
import Data.OrdPSQ (OrdPSQ)
import qualified Data.OrdPSQ as PSQ
import Data.Time (UTCTime, getCurrentTime)

import Network.DNS.Types

data Section = Answer | Authority deriving (Eq, Ord, Show)

type Key = (ShortByteString -- avoiding memory fragmentation
           ,TYPE
           ,Section)
type Prio = UTCTime

type Entry = Either DNSError [RData]

type DB = OrdPSQ Key Prio Entry

type Cache = R.Reaper DB (Key,Prio,Entry)

newCache :: Int -> IO Cache
newCache delay = R.mkReaper R.defaultReaperSettings {
    R.reaperEmpty  = PSQ.empty
  , R.reaperCons   = \(k, tim, v) psq -> PSQ.insert k tim v psq
  , R.reaperAction = prune
  , R.reaperDelay  = delay * 1000000
  , R.reaperNull   = PSQ.null
  }

lookupCache :: Key -> Cache -> IO (Maybe (Prio, Entry))
lookupCache key reaper = PSQ.lookup key <$> R.reaperRead reaper

insertCache :: Key -> Prio -> Entry -> Cache -> IO ()
insertCache key tim ent reaper = R.reaperAdd reaper (key,tim,ent)

-- Theoretically speaking, atMostView itself is good enough for pruning.
-- But auto-update assumes a list based db which does not provide atMost
-- functions. So, we need to do this redundant way.
prune :: DB -> IO (DB -> DB)
prune oldpsq = do
    tim <- getCurrentTime
    let (_, pruned) = PSQ.atMostView tim oldpsq
    return $ \newpsq -> foldl' ins pruned $ PSQ.toList newpsq
  where
    ins psq (k,p,v) = PSQ.insert k p v psq
