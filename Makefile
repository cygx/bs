build: manual.html
clean:; rm -f manual.html manual.html.tmp

manual.html: %.html: %.bs bs.p6
	perl6 bs.p6 $< >$@.tmp
	mv $@.tmp $@
