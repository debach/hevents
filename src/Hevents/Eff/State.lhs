Defines an effect to synchronize changes to a `Model`, following the [Freer](http://okmij.org/ftp/Haskell/extensible/more.pdf) and extensible monad
paper and library.

> {-# LANGUAGE DeriveFunctor #-}
> {-# LANGUAGE GADTs         #-}
> module Hevents.Eff.State(State, applyCommand, makeState, runState) where
> 
> import           Control.Concurrent.STM
> import           Control.Eff
> import           Control.Eff.Lift
> import           Data.Typeable
> import qualified Hevents.Eff.Model as M
> import           Hevents.Eff.Model hiding (init)
> import           Prelude hiding (init)

A `State` is parameterized by the type of `Model` it manages.

> data State m a where

Atomically apply  a given `Command` to given state and updates it, returning the result of the command
execution: `Either` and `Error` or an `Event`.

>   ApplyCommand :: (Model m) => TVar m -> Command m -> (Either (Error m) (Event m) -> a) -> State m a

Initializes a shared `Model` from given value.

>   Init         :: (Model m) =>                      (TVar m                     -> a) -> State m a
>   deriving (Typeable)

Boilerplate code to:

* Make `State m` a `Functor,
* Provide "smart" constructors.

> instance Functor (State m) where
>   f `fmap` (ApplyCommand m c k) = ApplyCommand m c (f . k)
>   f `fmap` (Init  k)            = Init (f . k)
> 
> applyCommand :: (Model m, Typeable m, Member (State m) r)
>                  => TVar m -> Command m -> Eff r (Either (Error m) (Event m))
> applyCommand c m = send $ inj $ ApplyCommand c m id
> 
> makeState :: (Model m, Typeable m, Member (State m) r) => Eff r (TVar m)
> makeState = send $ inj $ Init id

Effective computation on a `State m` which boils down to interpreting each `State` constructor's effect.
Because we are relying on `STM` computations we need to ensure the underlying `r` functor allows *lifting*
to the `STM` monad, which is expressed by the constraint `SetMember Lift (Lift STM) r`. In an earlier version
this was lifted to `IO` but this is not necessary and running in the `STM` has the effect that the result of
`runState` computation lives in STM, meaning operations are composed as a single memory transaction.

> runState :: (Model m, Typeable m, SetMember Lift (Lift STM) r) => Eff (State m :> r) w -> Eff r w
> runState = freeMap return (\ u -> handleRelay u runState interpret)
>   where

There is some boilerplate here as we could potentially factorize the `lift ... >>= runState . k` part into
a function. But this does not typecheck... This might have to do with the scope limitation of some type
variable in the `Eff` ?

>     interpret (ApplyCommand v c k) = lift (actAndApply v c) >>= runState . k
>     interpret (Init k)             = lift (newTVar M.init)  >>= runState . k

Low-level function to actually run the command against the model.

> actAndApply :: (Model m) => TVar m -> Command m -> STM (Either (Error m) (Event m))
> actAndApply v command = do
>   s <- readTVar v
>   let modifyState (KO er) = return $ Left er
>       modifyState (OK ev) =  do
>         let newView = s `apply` ev
>         writeTVar v newView
>         return $ Right ev
>   modifyState (s `act` command)