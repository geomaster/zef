test:
	cd t && busted .

test-coverage:
	rm -f t/luacov.{stats,report}.out
	cd t && busted --coverage .
	cd t && luacov

PHONY: test test-coverage
