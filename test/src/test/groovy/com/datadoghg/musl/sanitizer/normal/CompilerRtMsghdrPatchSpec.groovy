package com.datadoghg.musl.sanitizer.normal

import com.datadoghg.musl.sanitizer.MuslSanitizerProgram
import com.datadoghg.musl.sanitizer.MuslSanitizerSpecification

class CompilerRtMsghdrPatchSpec extends MuslSanitizerSpecification {
    def 'ASan sendmsg and recvmsg interceptors understand musl field widths'() {
        when:
        MuslSanitizerProgram program = harness.compileC(
            'samples/compiler_rt_msghdr.c',
            ['-O1', '-fsanitize=address'])
        def result = harness.run(program)

        then:
        result.exitCode == 0
        result.stdout.trim() == 'asan-msghdr-ok'
        program.hasWeakFunctionSymbol('sendmsg')
        program.hasWeakFunctionSymbol('recvmsg')
        !program.hasHiddenFunctionSymbol('sendmsg')
        !program.hasHiddenFunctionSymbol('recvmsg')
    }
}
