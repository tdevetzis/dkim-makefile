[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.md)

# DKIM Makefile

## _Makefile to generate and manage DKIM keys_

This is a simple makefile to help with DKIM housekeeping, suitable for small installations updating keys on a regular basis. Note that this is not a "hands-off" automated DKIM key rotation solution.

## Features

- Generate DKIM keys, *BIND* zone files, and *nsupdate* (DDNS) command files.
- Install/uninstall DKIM and zone files (active or revoked keys) into appropriate directories.
- Dynamically update DKIM resource records (add, delete, revoke, delete revoked).
- Save data and state in *tar* file for portable execution.
- Reasonably configurable.

## Quick Start

Generate the files:

```sh
make domains="foo.com bar.net mumble.org"
```
Files are in the *`YYYYMMDD`* subdirectory.

Install key and zone files for *Exim* and *BIND*:

```sh
make install DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
```

See [Usage](#usage) for more options.

## Configuration

Configuration parameters may be set as environment variables, in the top section of the Makefile, or in a separate configuration (makefile) as `make` variables (preferred). The Makefile will include (if present) `local.mk` followed by any other files ending in `.mk`. This is useful to set relatively static parameters once in `local.mk`:

```sh
domains := $(shell cat /etc/domains.txt)
selector := $(shell hostname)-2022
selector_suffix :=
DKIM_DIR = /etc/dkim
ZONE_DIR = /etc/bind/zones/$(DOMAIN)
DDNS_KEYFILE = /etc/bind/ddns-master.key
DDNS_SERVER = ns.example.com
```

These are applied for all new invocations, regardless of selector.[^1]

> Note: `local.mk` is included before any other `*.mk` files in order to ensure local variables are available to the latter.

[^1]: Once the files are created in the `selector` subdirectory, the [saved state](#saved-state) associated with the selector will override any subsequent changes to the `*.mk` files.

Parameters may also be passed to *make* via the command line in the usual way:

```sh
make domains="foo.com bar.net"
make install domains="bar.net" DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
```

Parameters are recursively expanded (except `domains`, `selector`, `selector_prefix`, and `selector_suffix`). See [Configuration Parameters](#configuration-parameters).

```sh
make install domains="foo.com" ZONE_DIR='/etc/bind/zones/$(DOMAIN)/dkim'
```

Note appropriate shell escapes in these cases.

### Precedence

Configuration parameters are read in the following order:

1. Environment variables.
2. Main `Makefile` (set defaults if not set).
3. `local.mk`
4. `*.mk` files.
5. Saved state.
6. Command line.

### The selector

The DKIM key, zone, and *nsupdate* files are associated with a selector (`selector` parameter), and are saved in a subdirectory with that name.

> Note: Valid characters for selectors include letters, digits, and hyphens. A selector cannot start or end with a hyphen and must be a maximum of 63 characters (including the prefix and suffix). See [RFC 1035].

[Selectors] can include periods (which become label boundaries when keys are retrieved via DNS). In this case each component of the selector (separated by periods) is limited to 63 characters.

#### The default selector

The default selector is generated based on the date: *`YYYYMMDD`*. This is a common practice and allows for simple inference when managing keys. An obvious pitfall occurs when rotating keys on the same day (should one be so inclined); it should be set accordingly to account for local operations.

##### The default selector prefix

None.

##### The default selector suffix

The default value is a hyphen followed by 8 random hexadecimal numbers (*`-xxxxxxxx`*). An example domain selector is then: `20230927-b2d4fe9c`.

### Configuration Parameters

Uppercase parameters are recursively expanded. The variable `DOMAIN` is available and set appropriately for each domain target. For example:

`DDNS_SERVER = ns.$(DOMAIN).`

(Ensure appropriate escapes for command line invocation.)

| Parameter | Default       | Notes
|:--------- |:------------- |:-----
| `domains` | _None._ | May be generated via a shell command (see Makefile).[^2]
| `selector` | *`YYYYMMDD`* | The DKIM selector. Default value is generated based on the date.[^2]
| `selector_prefix` | _None._ | Prepended to the DKIM selector (only in generated files).[^2]
| `selector_suffix` | *`-xxxxxxxx`* | Appended to DKIM selector (only in generated files). Default value is a hyphen-prepended random hexadecimal string (8 characters).[^2]
| `DOMAIN` | _Automatically set to the current domain._ | **Do not set directly**. Can be used in other parameters and will be expanded accordingly.
| `DKIM_FILENAME` | `$(DOMAIN).key` | Template for installed DKIM key file names. `$(DOMAIN).pem` is common.[^2]
| `ZONE_FILENAME` | `$(DOMAIN).dkim` | Template for installed zone file names.[^2]
| `DKIM_DIR` | `/etc/exim4/dkim/$(selector)` | Key installation directory.[^2]
| `ZONE_DIR` | `/etc/bind/zones/dkim/$(selector)` | Zone file installation directory.[^2]
| `DDNS_KEYFILE` | `/etc/bind/K$(DOMAIN).key` | TSIG authentication key used by *nsupdate* (for dynamic updates).[^2]
| `STATE_DIR` | _None._ | Directory included with *tar* bundle. See [Examples](#add-state-to-the-archive) for ideas.[^2]
| `DKIM_DEFAULTS` | `"V=DKIM1;k=rsa;h=sha256;t=s;"` | DKIM tags. *Note that the quotes and trailing slash are required*. This cannot be set via an environment variable and should be changed in a local `.mk` file if needed.[^2]
| `KEYSIZE` | `2048` | Private key size.[^2]
| `DDNS_SERVER` | `localhost` | DNS server for dynamic updates. Set this to use the dynamic update targets. See the Makefile for examples.[^2]
| `TTL` | _None._ | The TTL for zone file records. Leave blank (the default) to inherit from the parent zones or other nameserver settings.[^2]
| `NSUPDATE_TTL` | `60` | The TTL for dynamic updates. Note that it cannot be blank as it's required by *nsupdate* commands (and will be silently set to the default if so).[^2]

[^2]: These parameters are saved as part of the subdirectory containing the files. Subsequent invocations of make *with the same selector* will automatically use the [saved state](#saved-state).

## Usage

### Initial setup

- Create a directory for DKIM management.
- Clone this repository.
- Create a `local.mk` file and set any variable definitions that will remain (somewhat) static (see `local.mk.example`).
  - Common candidates:
    - `domains`, `DKIM_DIR`, `ZONE_DIR`, `DDNS_KEYFILE`, `DDNS_SERVER`.
    - `selector`, `selector_prefix`, `selector_suffix`.
  - Less common: `DKIM_DEFAULTS`,`dnsmode`, `keymode`, `install_dkim_flags`, `install_zone_flags`.

### Ongoing

- Create and install DKIM key and zone files (or dynamically update the DNS).
  - `make [domains="foo.com bar.net"]`
  - `make install` _(files)_
  - `make add` _(DDNS)_
- Do nameserver and mailserver housekeeping.
- Rotate the keys as desired.
  - Create and install new keys and zone files as above (**with a new selector**).
  - Delete or revoke the previous keys as desired. E.g.
    - `make uninstall selector="<previous-selector>"` _(files)_
    - `make revoke selector="<previous-selector>"` _(DDNS)_
	- Do nameserver and mailserver housekeeping.
- Lather, rinse, repeat.
- The directory will fill with `selector` subdirectories over time. Files may be deleted when no longer needed.
  - `make clean|realclean selector="<deprecated-selector>"`

The default target case generates DKIM, zone, and *nsupdate* files in the `selector` subdirectory. These files can then be installed (folded, spindled, and/or mutilated) as desired. Additional [targets](#targets) make it convenient to install/uninstall the key and zone files and dynamically update the DKIM records as appropriate for the installation. The subdirectory may be bundled (see the `tar` target) and invoked elsewhere and/or in the future as necessary (see [Examples](#examples)).

> Note: The selector present in the generated files includes the `selector_prefix` and `selector_suffix` components. These are not included in the directory names to simplify day-to-day usage.

Zone reloads, MTA restarts, etc. are not in scope for this project.[^3]

[^3]: The bottom of the Makefile contains a handful of utility targets that can (and should) be customized and augmented in a custom `.mk` file (e.g. `my-targets.mk`) for this purpose.

### Targets

**_default_**\
Build the DKIM keys, zone files, and DDNS (*nsupdate* command) files in the `selector` subdirectory.

**files**\
Build the DKIM keys and zone files only.

**ddns**\
Build the DKIM keys and DDNS files only.

**install**\
Install the (active) key and zone files into `DKIM_DIR` and `ZONE_DIR` respectively. The file modes are set per the following variables.

   | Variable             | Default  | Notes
   |:-------------------- |:-------- |:-----
   | `dnsmode`            | `644`    | File mode for installed zone files.
   | `keymode`            | `640`    | File mode for installed DKIM key files.
   | `install_dkim_flags` | _None._  | Extra flags to *install* (e.g. `"-o root -g Debian-exim"`).
   | `install_zone_flags` | _None._  | Extra flags to *install* (e.g. `"-o root -g bind"`).

**install-keys**\
Install the key files into `DKIM_DIR` (for mailserver configuration).

**install-zones install-zones-key**\
Install the zone files with active keys into `ZONE_DIR` (for nameserver configuration).

**install-zones-revoke**\
Install the zone files with revoked keys into `ZONE_DIR` (for nameserver configuration).

**uninstall**\
Uninstall (remove) the key and zone files.

**uninstall-keys**\
Uninstall (remove) the key files. `DKIM_DIR` is not removed.

**uninstall-zones**\
Uninstall (remove) the zone files. `ZONE_DIR` is not removed.

**add**\
Dynamically add the DKIM records to the appropriate zone on `DDNS_SERVER` using `DDNS_KEYFILE` (appropriate grants must be in place). Uses *nsupdate*.

**delete**\
Dynamically delete the DKIM records from the appropriate zone on `DDNS_SERVER` using `DDNS_KEYFILE` (appropriate grants must be in place). Uses *nsupdate*.

**revoke**\
Dynamically revoke the DKIM records in the appropriate zone on `DDNS_SERVER` using `DDNS_KEYFILE` (appropriate grants must be in place). Revocation entails publishing the DKIM record with a blank key (`"p="`). Uses *nsupdate*.

**delete-revoked**\
Dynamically delete the revoked DKIM records in the appropriate zone on `DDNS_SERVER` using `DDNS_KEYFILE` (appropriate grants must be in place). Uses *nsupdate*.
Typically used after the keys have been revoked for some transitory period.

**tar**\
Package the files in a compressed *tar* file (`<selector>.tar.gz`). The creation state (including any `*.mk` files) and `STATE_DIR` are included so that the archive may be unpacked and run at a later date (and/or on another machine) with predictable results (see [Examples](#examples)).

**clean**\
Remove the subdirectory and files associated with the `selector`.

   > **Caution**: Unless installed/copied elsewhere, the files cannot be recovered.
    
**realclean**\
Like *clean*, but remove the *tar* file as well.

   > **Caution**: Unless installed/copied elsewhere, the files cannot be recovered.

**state**\
Save the state variables in the `selector` subdirectory. See [Saved State](#saved-state).

The `add`, `delete`, `revoke`, and `revoke-deleted`  targets use the generated `*.{add,del,rev,delrev}-nsupdate` files in the `selector` subdirectory.

### Saved State
Once the keys and zone files are generated, the creation-time state is preserved in the subdirectory in order to capture parameters for future invocations. For example, one might generate and install files for a set of domains and selector:

```sh
make domains="$(cat /etc/domainlist)" selector="$(date +%Y%m%d)"
```

The former may change over time, and the latter will change every day. **For a given selector**, the state is saved across future invocations. See [Examples](#examples).

The following variables are captured in the saved state:
- `domains`
- `selector`
- `selector_prefix`
- `selector_suffix`
- `DKIM_FILENAME`
- `ZONE_FILENAME`
- `DKIM_DIR`
- `ZONE_DIR`
- `DDNS_KEYFILE`
- `STATE_DIR`
- `DKIM_DEFAULTS`
- `DDNS_SERVER`
- `KEYSIZE`
- `TTL`
- `NSUPDATE_TTL`

> Note that the automatically-generated variable `DOMAIN` is handled appropriately across invocations and can be included in variable declarations as described above.

This makes it convenient to set the appropriate variables once and not have to do so on subsequent invocations:

```sh
make selector="202202" domains="$(cat /etc/domainlist)" STATE_DIR="my-keys" NS_KEY_FILE='$(STATE_DIR)/$(DOMAIN).key' ZONE_DIR='/etc/bin/zones/$(DOMAIN)/$(selector)'
make install selector="202202"
```

In particular, one can unpack a file generated with the `tar` target and simply invoke make on the included subdirectory (i.e, the selector):

```sh
make install selector="<subdirectory>"
```

Note that per standard *make* behavior, variables (even saved state) may be overridden on the command line at any time:

```sh
make install DKIM_DIR="/etc/dkim/keys"
```

#### State file

The saved state is stored in the file `<selector>/._vars.mk` when the files are created and included in subsequent invocations. For convenience, the `state` target is available to create this file prior to invoking the other targets:

```sh
make state selector="202202" domains="$(cat /etc/domainlist)" STATE_DIR="my-keys" DDNS_KEYFILE='$(STATE_DIR)/$(DOMAIN).key' ZONE_DIR='/etc/bin/zones/$(DOMAIN)/$(selector)'
```

```sh
make selector="202202"
make install selector="202202"
```

> Note: this file is loaded _after_ (and will override) any local `*.mk` files.

## Examples

### Create DKIM and zone files with a custom selector

```sh
make domains="foo.com bar.net" selector="acme-external"
```

Example generated selector: *`acme-external-dab5e03b`*

#### Get rid of the default selector suffix

```sh
make domains="foo.com bar.net" selector="acme-external" selector_suffix=
```

Generated selector: *`acme-external`*

### Create and install DKIM and zone files with the default selector

```sh
make domains="foo.com bar.net" DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
make install
```

### Install DKIM and zone files and revoke or delete at a later date

```sh
make domains="foo.com bar.net" DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
make install
```
The files will be created in a subdirectory named *`YYYMMDD`* (for example, `20230214`) and installed in the specified directories.

#### Revoke

```sh
make install-zones-revoke selector="20230214"
```

#### Delete

```sh
make uninstall selector="20230214"
```

### Install the DKIM and zone files on another machine

```sh
make tar domains="foo.com bar.net mumble.org" DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
```

A tar file called `<selector>.tar.gz` is created. This file may be copied and extracted elsewhere. Assuming a selector of `20230214`:

```sh
mkdir /tmp/dkim
cd /tmp/dkim
tar -xzvf ~/Downloads/20230214.tar.gz
make install selector="20230214"
```
`domains`, `DKIM_DIR`, and `ZONE_DIR` are "remembered" from when the archive was created.

### Create DKIM and zone files and dynamically update the DNS

Configuring nameservers for [dynamic updates] is beyond the scope of this document. Assuming the framework is in place:

```sh
make domains="foo.com bar.net" DDNS_SERVER="ns.example.com" DDNS_KEYFILE='/etc/bind/K$(DOMAIN).key'
```

#### Add the records

```sh
make add
```

#### Revoke the records

The records can later be revoked:

```sh
make revoke selector="<selector>"
```

And the revoked records later deleted:

```sh
make delete-revoked selector="<selector>"
```

#### Delete the records

Delete the DKIM records directly without revocation:

```sh
make delete selector="<selector>"
```

### Add state to the archive

The `STATE_DIR` variable specifies a directory to include in the archive. For example, one possible use case adds the (perhaps temporary) TSIG keys to this directory for portable execution; assuming the subdirectory `tsig-keys` contains the files `Kfoo.com.key` and `Kbar.net.key`:

```sh
make tar domains="foo.com bar.net" STATE_DIR="tsig-keys" NS_KEY_FILE='$(STATE_DIR)/K$(DOMAIN).key'
```

The tar file can be copied and utilized elsewhere. Once unpacked the TSIG keys are available:

```sh
make install-keys selector=<selector>
make add selector=<selector>
```

> **Caution**: While the Makefile sets the key (and tar) file permissions appropriately, sensitive files must always be handled securely.

### Install DKIM and zone files for selected domains and dynamically update others

```sh
make domains="foo.com bar.net mumble.org" DKIM_DIR="/etc/exim4/dkim" ZONE_DIR="/etc/bind/zones/dkim"
make install domains="foo.com bar.net"
make install-keys add domains="mumble.org"
```

#### Delete (or revoke) the previous records

Assuming the subdirectory for the previous set of records is named `201612` and we have new TSIG keys:

```sh
make uninstall-keys delete selector="201612" domains="mumble.org" DDNS_KEYFILE='/etc/bind/newkeys/K$(DOMAIN).key'
```

## Caveats

GNU make and OpenSSL are required.

This is not an automated key management solution. It is intended to simplify manual key management.

It's a Makefile. While it's legal to do something like `make TTL="warmbucketofspit"`, it is strongly discouraged. The user is trusted to Know What They're Doing.

## Bugs

Probably. Please open an issue or pull request.

## Contributing

Pull requests welcome, although feature-creep better left to automated systems is discouraged (it's just a makefile, after all).

## License

This project is licensed under the terms of the MIT license. See the [LICENSE](LICENSE.md) file for license rights and limitations.

[//]: # (Reference links)

   [dynamic updates]: <https://bind9.readthedocs.io/en/v9.18.18/chapter6.html#dynamic-update>
   [selectors]: <https://datatracker.ietf.org/doc/html/rfc6376#section-3.1>
   [RFC 1035]: <https://datatracker.ietf.org/doc/html/rfc1035#section-2.3.1>
