build: docs/index.html docs/manual.css
clean:; rm -f manual.html manual.html.tmp

docs/index.html: manual.html; cp $< $@
docs/manual.css: docs/%: %; cp $< $@

manual.html: %.html: %.bs bs.p6
	perl6 bs.p6 $< >$@.tmp
	mv $@.tmp $@
