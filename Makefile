manual.html: %.html: %.bs bs.p6
	perl6 bs.p6 $< >$@.tmp
	mv $@.tmp $@
