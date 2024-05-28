module Pipewire.SPA.Utilities.Dictionary where

import Data.Text (Text)
import Data.Vector qualified as V
import Data.Vector.Storable.Mutable qualified as VM
import Foreign (Ptr)
import Foreign.C.Types
import Language.C.Inline qualified as C

import Pipewire.Internal
import Pipewire.SPA.Utilities.CContext

newtype SpaDict = SpaDict (Ptr SpaDictStruct)

C.context (C.baseCtx <> C.vecCtx <> pwContext)
C.include "<spa/utils/dict.h>"

-- | Read 'SpaDict' keys/values
spaDictRead :: SpaDict -> IO (V.Vector (Text, Text))
spaDictRead (SpaDict spaDict) = do
    -- Read the dictionary size
    propSize <-
        fromIntegral
            <$> [C.exp| int{$(struct spa_dict* spaDict)->n_items}|]

    -- Create two mutable vectors to store the key and value char* pointer.
    vecKey <- VM.new propSize
    vecValue <- VM.new propSize

    -- Fill the vectors
    [C.block| void {
      // The Haskell spaDict
      struct spa_dict *spa_dict = $(struct spa_dict* spaDict);

      // The Haskell vectors
      const char** keys = $vec-ptr:(const char **vecKey);
      const char** values = $vec-ptr:(const char **vecValue);

      // Use the provided 'spa_dict_for_each' macro to traverse the c struct
      const struct spa_dict_item *item;
      int item_pos = 0;
      spa_dict_for_each(item, spa_dict) {
        keys[item_pos] = item->key;
        values[item_pos] = item->value;
        item_pos += 1;
      };
    }|]

    -- Convert the CString vectors into a vector of Text (key,value) tuples
    let readCString pos = do
            key <- peekCString =<< VM.read vecKey pos
            val <- peekCString =<< VM.read vecValue pos
            pure (key, val)
    V.generateM propSize readCString