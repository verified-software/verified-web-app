.PHONY: verify check-evidence scala-check
verify:
	bash scripts/build.sh
check-evidence:
	bash scripts/check-evidence.sh
scala-check:
	mkdir -p build/scala-source build/scala-generated build/scala-classes
	sed 's/--safe //g' agda/TenantCore.agda > build/scala-source/TenantCore.agda
	cat scripts/tenant-scala-pragmas.agda.inc >> build/scala-source/TenantCore.agda
	agda2scala --no-libraries --erasure --no-projection-like --ignore-interfaces --scala-dialect=Scala3 --out-dir=build/scala-generated -i vendor/agda2hs-base -i build/scala-source build/scala-source/TenantCore.agda
	cmp build/scala-generated/TenantCore.scala scala/TenantCore.scala
	scalac -d build/scala-classes scala/MaybeCompat.scala scala/TenantCore.scala scala/TenantSmoke.scala
	scala -classpath build/scala-classes TenantSmoke
