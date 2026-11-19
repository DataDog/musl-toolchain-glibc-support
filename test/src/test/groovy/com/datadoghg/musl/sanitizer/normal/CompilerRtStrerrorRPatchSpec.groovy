package com.datadoghg.musl.sanitizer.normal

import com.datadoghg.musl.sanitizer.MuslSanitizerProgram
import com.datadoghg.musl.sanitizer.MuslSanitizerSpecification

class CompilerRtStrerrorRPatchSpec extends MuslSanitizerSpecification {
    def 'MSan strerror_r interceptor uses the POSIX signature on musl'() {
        when:
        MuslSanitizerProgram program = harness.compileC(
            'samples/compiler_rt_strerror_r.c',
            ['-O1', '-fsanitize=memory', '-fPIE', '-pie'])
        def result = harness.run(program)

        then:
        result.exitCode == 0
        result.stdout.trim() == 'msan-strerror_r-ok'
    }
}
