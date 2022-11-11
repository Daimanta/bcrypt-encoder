# Bcrypt encoder

Bcrypt encoder hashes password with the bcrypt algorithm. Also allows checking if a password matches a provided hash.

## Usage

```
Usage: bcrypt-encoder [OPTION]
 Hashes password with the bcrypt algorithm. Also allows checking if a password matches a provided hash.

 If arguments are possible, they are mandatory unless specified otherwise.
        -h, --help              Display this help and exit.
        -r, --rounds <NUM>      Indicates the log number of rounds, 1<= rounds <= 31. Default value is 10.
        -c, --check <HASH>      Prompts for a password. 'true' or 'false' will be returned whether the password matches the hash. Cannot be combined with -er.
        -e, --encrypt           Prompts for a password. The result will be a bcrypt hash of the password. Cannot be combined with -c. Default option.
```