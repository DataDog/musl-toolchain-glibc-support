package org.cataphract.musl.sanitizer.normal

import org.cataphract.musl.sanitizer.MuslSanitizerProgram
import org.cataphract.musl.sanitizer.MuslSanitizerSpecification

class AsanUbsanCxxRuntimeSpec extends MuslSanitizerSpecification {
    def setupSpec() {
        harness.copyResourceToBuildEnvironment(
            'policies/sanitizer-musl-clang.conf', '/etc/musl-clang.conf')
    }

    def 'ASan and UBSan initialize the C++ standard library'() {
        when:
        MuslSanitizerProgram program = harness.compileCpp(
            'samples/asan_ubsan_cxx_standard_library.cpp',
            ['-O1', '-g', '-fsanitize=address,undefined,vptr',
             '-fno-sanitize=function'])
        def result = harness.run(
            program, [], ['UBSAN_OPTIONS': 'halt_on_error=1'])

        then:
        result.exitCode == 0
        result.stdout.trim() == 'asan-ubsan-cxx-standard-library-ok'

        and: 'the ASan-instrumented shared runtimes'
        program.runtimeLibraries.keySet().containsAll(
            ['libc++.so.1', 'libc++abi.so.1', 'libunwind.so.1'])
    }
}
