# leave these lines alone
.SUFFIXES: .erl .beam .yrl

.erl.beam:
	erlc -W $<

HOSTNAME = $(shell hostname)

ERL = erl -boot start_sasl -config system -setcookie carrier 
#WERL = werl -boot start_sasl -config system -setcookie carrier

WERL = werl -setcookie carrier

all: compile

compile: ${MODS:%=%.beam} 
	erl -make	

## run an application from the makefile

ms:compile
	${ERL} -pa ../lib -sname  ${HOSTNAME}ms -s crypto start -s app_meta_server start 
	
wms:compile
	${WERL} -pa ../lib -sname  ${HOSTNAME}ms -s crypto start -s app_meta_server start 
	
# remove all the code

clean:	
	rm -rf *.beam erl_crash.dump

