# Diagnostic codes

Every problem ApolloShell reports about a config carries a code, such as `error[A201]`. The code stays the same across versions, even when the wording of the message changes.

| Code | Meaning |
| --- | --- |
| `A001` | More problems of the same kind exist and are not listed. |
| `A101` | The file is not valid KDL. |
| `A102` | An included file does not exist. |
| `A103` | A config file exists but cannot be read. |
| `A104` | A config file is larger than the size limit. |
| `A105` | An include path leads outside the config folder. |
| `A106` | An include path must be relative and cannot start with ~. |
| `A107` | Files include each other in a circle. |
| `A108` | The config includes more files than allowed. |
| `A109` | A glob pattern matched no files. |
| `A110` | An include or style node is written wrongly. |
| `A111` | A builtin: or pkg: path lacks the id or the path. |
| `A112` | A package includes a file outside the package. |
| `A113` | KDL type annotations are reserved and not allowed. |
| `A114` | The config grows too large or too deep once includes and uses are expanded. |
| `A115` | A stylesheet file does not exist. |
| `A201` | The node name is not known here. |
| `A202` | The node has no property with this name. |
| `A203` | A required argument is missing. |
| `A204` | The node takes fewer arguments. |
| `A205` | An argument has the wrong type. |
| `A206` | A property has the wrong type. |
| `A207` | A required property is missing. |
| `A208` | The node cannot have children. |
| `A209` | The node is not allowed at this place. |
| `A210` | The name is experimental and may change in a later version. |
| `A211` | The name is reserved by the language. |
| `A212` | A name hides a provider with the same name. |
| `A213` | Lua scripting is reserved for a later version. |
| `A214` | The menu source kind is not known. |
| `A215` | No {…} expression is allowed at this place. |
| `A301` | A define, param, slot, use or fill name is missing or invalid. |
| `A302` | A define in a package should carry the package id as prefix. |
| `A303` | A define declares the same parameter twice. |
| `A304` | type= names a type that does not exist. |
| `A305` | The default of a parameter does not match its type. |
| `A306` | use names a define that does not exist. |
| `A307` | Defines use each other in a circle. |
| `A308` | use passes a parameter the define does not declare. |
| `A309` | use passes a value of the wrong type. |
| `A310` | use does not pass a parameter without default. |
| `A311` | fill names a slot the define does not have. |
| `A312` | The same slot is filled twice. |
| `A313` | A use with an expression as name is not allowed at this place. |
| `A401` | An expression inside {…} cannot be read. |
| `A402` | An expression grows too large once its filters are expanded. |
| `A403` | An expression starts with a name that does not exist here. |
| `A404` | An expression reads a var that is not declared. |
| `A405` | A provider has no field with this name. |
| `A406` | A filter gets the wrong number or kind of arguments. |
| `A407` | The filter name is not known. |
| `A408` | A filter node is written wrongly. |
| `A409` | A filter name is already taken. |
| `A410` | A var node is written wrongly. |
| `A411` | A derived var cannot be persisted. |
| `A412` | An expression failed while the shell was running. |
| `A501` | The same thing is defined twice without override=#true. |
| `A502` | override=#true replaces nothing. |
| `A503` | disable needs surface=, bind= or on=. |
| `A504` | disable names something that does not exist. |
| `A505` | An element has more than one menu. |
| `A506` | An id consists only of digits. |
| `A507` | Two elements in a surface have the same id. |
| `A508` | A switch contains something other than case and one final default. |
| `A509` | A package uses an action that starts programs or controls apps. |
| `A510` | Children of a list must be - entries. |
| `A511` | A name ends with the reserved suffix -error. |
| `A512` | require names a version that cannot be read. |
| `A513` | The config needs a newer ApolloShell. |
| `A601` | A stylesheet is larger than the size limit and is not used. |
| `A602` | A stylesheet cannot be read at this place. |
| `A603` | A stylesheet nests deeper than allowed. |
| `A604` | A style property has an invalid value. |
| `A605` | The theme sets a token the config does not declare. |
| `A701` | settings.kdl is not valid KDL. |
| `A702` | settings.kdl sets the same node twice. |
| `A703` | A node in settings.kdl has a value of the wrong type. |
| `A704` | settings.kdl contains an unknown node. |
| `A705` | settings.kdl names a config that does not exist. |
| `A706` | A state file cannot be read. |
| `A707` | A state file stores the same var twice. |
| `A708` | A stored value does not match the var's type. |
| `A709` | An unreadable state file could not be set aside. |
| `A710` | Settings from ApolloShell 0.1 could not be imported. |
| `A711` | The built-in Marketplace surfaces did not load. |
| `A801` | apollo check was given a folder it cannot check. |
| `A802` | apollo check was given a fixture that does not exist. |
| `A803` | apollo check cannot read a file and uses defaults. |
