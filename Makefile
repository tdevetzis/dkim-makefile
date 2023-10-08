# Copyright (c) 2023 Taso N. Devetzis
# This file is licensed under the terms of the MIT license.

#
## Begin config.
#

# Installed DKIM key and zone file names.
#
DKIM_FILENAME	?= $(DOMAIN).key
ZONE_FILENAME	?= $(DOMAIN).dkim

# Directories, permissions, and keys for install target.
#
DKIM_DIR	?= /etc/exim4/dkim/$(selector)
ZONE_DIR	?= /etc/bind/zones/dkim/$(selector)
DDNS_KEYFILE	?= /etc/bind/K$(DOMAIN).key

# Installed file modes.
#
keymode		?= 640
dnsmode		?= 644
#install_dkim_flags	?= -o root -g Debian-exim
#install_zone_flags	?= -o root -g bind

# (Optional) directory to include in tar file.
#
#STATE_DIR	?= 

# DKIM defaults.  NOTE QUOTES AND TRAILING SEMICOLON.
#
DKIM_DEFAULTS	= "v=DKIM1;k=rsa;h=sha256;t=s;"
KEYSIZE		?= 2048

# DNS server for dynamic DKIM record updates (nsupdate).  Can be set
# per domain.
#
#DDNS_SERVER	= ns.foo.com
#DDNS_SERVER	= ns.$(DOMAIN)
#DDNS_SERVER	= $(shell dig -tNS $(DOMAIN) +short | head -1)
DDNS_SERVER	?= localhost

# Domains to operate on.
#
#domains	:= foo.com bar.net mumble.org
#domains	:= $(shell hostname -d)
#domains	:= $(shell ldapsearch -LLL -H ldapi:/// -x -b "dc=sendmail,dc=org" "(sendmailMTAClassName=VirtHost)" | egrep '^sendmailMTAClassValue:' | awk '{print $$2}')
#domains	:= $(shell egrep '^\s*zone\s+' /etc/bind/named.conf.local | awk '{print $$2}' | sed 's/"//g')

# DKIM selector.  Files will be generated in this subdirectory (w/o
# prefix and suffix).
#
selector	?= $(shell date +%Y%m%d)
selector_prefix	?= 
selector_suffix	?= -$(shell cat /dev/random | head -c4 | od -An -xv | tr -d ' \n')

# Zone file and nsupdate TTLs.  NSUPDATE_TTL is required by nsupdate,
# TTL can be blank to use the parent zone file defaults, et.al.
#
#TTL		?= 
NSUPDATE_TTL	?= 60

#
## End config.
#

# DKIM zone file format.
#
DKIM_ZONE	= $(RR) $(TTL) IN TXT $(DKIM_DEFAULTS) $(SPLIT_KEY)

# nsupdate commands.
#
define NSUPDATE_ADD_DEL	=
server $(SERVER)
zone $(DOMAIN).
update $(_nsop) $(RR).$(DOMAIN). $(_NSUPDATE_TTL) IN TXT $(DKIM_DEFAULTS) $(SPLIT_KEY)
send
endef
define NSUPDATE_REV =
server $(SERVER)
zone $(DOMAIN).
update delete $(RR).$(DOMAIN). $(_NSUPDATE_TTL) IN TXT $(DKIM_DEFAULTS) $(SPLIT_KEY)
update add $(RR).$(DOMAIN). $(_NSUPDATE_TTL) IN TXT $(DKIM_DEFAULTS) $(REVOKED_KEY)
send
endef

# .SILENT:

# Load creation time params.
#
statefile	:= $(selector)/._vars.mk
_mk		:= $(filter-out local.mk, $(wildcard *.mk))
-include local.mk
-include $(_mk)
-include $(statefile)

domains		:= $(domains)
selector	:= $(selector)
selector_prefix	:= $(selector_prefix)
selector_suffix	:= $(selector_suffix)
override _NSUPDATE_TTL	:= $(or $(NSUPDATE_TTL), 60)

# Utils.
#
_selector_regex	:= ^[a-zA-Z0-9]+([.A-Za-z0-9-]*[A-Za-z0-9]+)*$
check_selector	= $(if $(shell echo $(1) | egrep '$(_selector_regex)'),,$(error Bad selector: "$(1)"))

privfiles	:= $(addsuffix .key, $(domains))
pubfiles	:= $(addsuffix .pem, $(domains))
dnsfiles	:= $(addsuffix .dkim, $(domains))
dnskeyfiles	:= $(addsuffix .dkim.key, $(domains))
dnsrevfiles	:= $(addsuffix .dkim.rev, $(domains))
nsaddfiles	:= $(addsuffix .nsupdate.add, $(domains))
nsdelfiles	:= $(addsuffix .nsupdate.del, $(domains))
nsrevfiles	:= $(addsuffix .nsupdate.rev, $(domains))
nsdelrevfiles	:= $(addsuffix .nsupdate.delrev, $(domains))
privkeys	:= $(addprefix $(selector)/, $(privfiles))
pubkeys		:= $(addprefix $(selector)/, $(pubfiles))
dnskeys		:= $(addprefix $(selector)/, $(dnskeyfiles))
dnsrevs		:= $(addprefix $(selector)/, $(dnsrevfiles))
nsadd		:= $(addprefix $(selector)/, $(nsaddfiles))
nsdel		:= $(addprefix $(selector)/, $(nsdelfiles))
nsrev		:= $(addprefix $(selector)/, $(nsrevfiles))
nsdelrev	:= $(addprefix $(selector)/, $(nsdelrevfiles))
dns		:= $(dnskeys) $(dnsrevs)
ns		:= $(nsadd) $(nsdel) $(nsrev) $(nsdelrev)

KEY = $(shell sed -e '/-\{1,\}BEGIN PUBLIC KEY-\{1,\}/d' -e '/-\{1,\}END PUBLIC KEY-\{1,\}/d' $< | tr -d '\n')
SPLIT_KEY = $(addprefix ", $(addsuffix ", p=$(shell echo $(KEY) | fold -w253)))
REVOKED_KEY = "p="
domain_selector = $(selector_prefix)$(selector)$(selector_suffix)
RR = $(domain_selector)._domainkey
$(ns): DOMAIN = $(*F)
$(ns): SERVER = $(or $(DDNS_SERVER), localhost)
$(nsdelrev) $(dnsrevs): KEY = 
$(nsadd) $(nsdel) $(nsdelrev): NSUPDATE = $(NSUPDATE_ADD_DEL)
$(nsrev): NSUPDATE = $(NSUPDATE_REV)
$(nsadd): _nsop = add
$(nsdel) $(nsdelrev): _nsop = del
state $(statefile): DOMAIN := $$(DOMAIN)

.PHONY: all state clean realclean install install-keys install-zones install-zones-key install-zones-revoke uninstall uninstall-keys uninstall-zones add delete revoke delete-revoked

all: state files ddns

files ddns: state

state: $(statefile) ;

files: $(dns) ;

ddns: $(ns) ;

$(privkeys):
	umask 066 && openssl genrsa -out $@ $(KEYSIZE) > /dev/null 2>&1

$(pubkeys): %.pem: %.key
	$(call check_selector,$(domain_selector))
	openssl rsa -in $< -out $@ -pubout -outform PEM > /dev/null 2>&1

$(dnskeys): %.dkim.key: %.pem
	$(file >$@,$(DKIM_ZONE))
	@:

$(dnsrevs): %.dkim.rev: %.pem
	$(file >$@,$(DKIM_ZONE))
	@:

$(nsadd): %.nsupdate.add: %.pem
	$(file >$@,$(NSUPDATE))
	@:

$(nsdel): %.nsupdate.del: %.pem
	$(file >$@,$(NSUPDATE))
	@:

$(nsrev): %.nsupdate.rev: %.pem
	$(file >$@,$(NSUPDATE))
	@:

$(nsdelrev): %.nsupdate.delrev: %.pem
	$(file >$@,$(NSUPDATE))
	@:

$(selector):
	$(call check_selector,$@)
	mkdir $@

$(statefile): | $(selector)
	$(file >$@,domains=$(domains))
	$(file >>$@,selector=$(selector))
	$(file >>$@,selector_prefix=$(selector_prefix))
	$(file >>$@,selector_suffix=$(selector_suffix))
	$(file >>$@,DKIM_FILENAME=$(DKIM_FILENAME))
	$(file >>$@,ZONE_FILENAME=$(ZONE_FILENAME))
	$(file >>$@,DKIM_DIR=$(DKIM_DIR))
	$(file >>$@,ZONE_DIR=$(ZONE_DIR))
	$(file >>$@,DDNS_KEYFILE=$(DDNS_KEYFILE))
	$(file >>$@,STATE_DIR=$(STATE_DIR))
	$(file >>$@,DKIM_DEFAULTS=$(DKIM_DEFAULTS))
	$(file >>$@,DDNS_SERVER=$(DDNS_SERVER))
	$(file >>$@,KEYSIZE=$(KEYSIZE))
	$(file >>$@,TTL=$(TTL))
	$(file >>$@,NSUPDATE_TTL=$(NSUPDATE_TTL))
	@:

tar: all
	umask 066 && tar acpf $(selector).tar.gz Makefile $(wildcard *.mk) $(selector) $(STATE_DIR)

clean:
	rm -rf $(selector)

realclean: clean
	rm -rf $(selector).tar.gz

install: install-keys install-zones

install-zones: install-zones-key

uninstall: uninstall-keys uninstall-zones

_INSTALL_DKIM_CMD	= install -D $(install_dkim_flags) -m $(keymode)
_INSTALL_ZONE_CMD	= install -D $(install_zone_flags) -m $(dnsmode)
_UNINSTALL_DKIM_CMD	= $(RM)
_UNINSTALL_ZONE_CMD	= $(RM)

# Ephemeral targets in order to use pattern rules to extract stem
# components.
#
_dkim_key = $(addsuffix ._dkim_key_, $(privkeys))
_zone_key = $(addsuffix ._zone_key_, $(dnskeys))
_zone_rev = $(addsuffix ._zone_rev_, $(dnsrevs))
_nsadd_dyn = $(addsuffix ._nsupdate_, $(nsadd))
_nsdel_dyn = $(addsuffix ._nsupdate_, $(nsdel))
_nsrev_dyn = $(addsuffix ._nsupdate_, $(nsrev))
_nsdelrev_dyn = $(addsuffix ._nsupdate_, $(nsdelrev))

install-keys: _cmd = $(_INSTALL_DKIM_CMD)
install-zones-key install-zones-revoke: _cmd = $(_INSTALL_ZONE_CMD)
uninstall-keys:	_cmd = $(_UNINSTALL_DKIM_CMD)
uninstall-zones: _cmd = $(_UNINSTALL_ZONE_CMD)
install-keys install-zones-key install-zones-revoke: _src = $<

install-keys uninstall-keys: $(_dkim_key)
install-zones-key uninstall-zones: $(_zone_key)
install-zones-revoke: $(_zone_rev)
add: $(_nsadd_dyn)
delete: $(_nsdel_dyn)
revoke: $(_nsrev_dyn)
delete-revoked: $(_nsdelrev_dyn)

$(_dkim_key) $(_zone_key) $(_zone_rev) $(_nsadd_dyn) $(_nsdel_dyn) $(_nsrev_dyn) $(_nsdelrev_dyn): DOMAIN = $(*F)

$(_dkim_key): %.key._dkim_key_: %.key
	$(_cmd) $(_src) $(DKIM_DIR)/$(DKIM_FILENAME)
$(_zone_key): %.dkim.key._zone_key_: %.dkim.key
	$(_cmd) $(_src) $(ZONE_DIR)/$(ZONE_FILENAME)
$(_zone_rev): %.dkim.rev._zone_rev_: %.dkim.rev
	$(_cmd) $(_src) $(ZONE_DIR)/$(ZONE_FILENAME)

$(_nsadd_dyn): %.nsupdate.add._nsupdate_: %.nsupdate.add
	nsupdate -k $(DDNS_KEYFILE) $<
$(_nsdel_dyn): %.nsupdate.del._nsupdate_: %.nsupdate.del
	nsupdate -k $(DDNS_KEYFILE) $<
$(_nsrev_dyn): %.nsupdate.rev._nsupdate_: %.nsupdate.rev
	nsupdate -k $(DDNS_KEYFILE) $<
$(_nsdelrev_dyn): %.nsupdate.delrev._nsupdate_: %.nsupdate.delrev
	nsupdate -k $(DDNS_KEYFILE) $<

# Various utility targets.  Copy into "<something>.mk" and
# customize/augment.
#
.PHONY: _lookup _reloadzones _reloadmta

_lookup:
	-@for i in $(domains); do echo "$(RR).$$i" && dig +short "$(RR).$$i." txt; done

_reloadzones:
	@for i in $(domains); do rndc reload "$$i"; done

_reloadmta:
	# service exim reload
	# /etc/init.d/exim reload
	systemctl reload exim4.service

# You've scrolled too far.
#
