# data-realize

A `unit` project scaffold for **data representation realization**.

This project explores a realization layer for known data languages with known decoders:

- JSON
- TOML
- JSON Lines
- later: frontend-defined grammars / parselex-style combiners

The guiding idea is:

> compile representation meaning into a decode machine, then realize that machine under a host contract.

Initial host contracts:

- `ReturnValueContract()`
- `AssignGlobalContract(name)`
- `PatchGlobalContract(name)`

So the intended lower shape is:

```text
DataRealizeSource
  -> check
DataRealizeChecked
  -> define_machine
DataRealizeMachine
  -> prepare_install
DataRealizeLua
  -> install
installed artifact
```

## Domain summary

### Authored nouns

- binding
- input source
- representation language
- realization contract
- package mode

### Identity nouns

- `Binding`

### Sum types

- `InputSource`
- `RepresentationLanguage`
- `RealizationContract`
- `PackageMode`

### Intended leaf constraints

The decode/install leaf should receive:

- one known decode machine family
- one known realization contract
- one known package mode
- already-chosen input-source handling

It should not need to rediscover:

- what language is being decoded
- whether the result is returned vs assigned vs patched
- what artifact family is being installed

## Initial scope

This is an initial scaffold only.

Planned next steps:

1. `DataRealizeSource.Spec:check()`
2. `DataRealizeChecked.Spec:define_machine()`
3. `DataRealizeMachine.Spec:prepare_install()`
4. `DataRealizeLua.Spec:install()`

Likely future extensions:

- frontend-defined grammar decoders
- parselex / parser-combiner-fed machines
- FFI struct targets
- environment/slot contracts beyond globals
- explicit shape-key vs artifact-key caching
