package com.datadoghg.musl.sanitizer.toolchain

import com.datadoghg.musl.sanitizer.MuslSanitizerProgram
import com.datadoghg.musl.sanitizer.MuslSanitizerSpecification
import org.testcontainers.containers.Container
import spock.lang.Unroll

/**
 * Covers the link-time policy itself rather than sanitizer behavior. The other
 * sanitizer specs select a library directory explicitly to isolate compiler-rt
 * behavior, so they cannot prove that MUSL_CLANG_SANITIZE selects it or that
 * the reduced libc entry retains the downstream compatibility archive.
 */
class SanitizerLinkPolicySpec extends MuslSanitizerSpecification {
    private static final String ASAN_DIRECTORY = '/usr/asan/lib'
    private static final String MSAN_DIRECTORY = '/usr/msan/lib'
    private static final String ASAN_POLICY =
        'policies/sanitizer-musl-clang.conf'
    private static final String MSAN_POLICY =
        'policies/msan-musl-clang.conf'
    private static final String WORK_DIRECTORY = '/tmp/sanitizer-link-policy'
    private static final String DOWNSTREAM_ARCHIVE =
        '/usr/lib/libadditional_compat.a'
    private static final String LIBC_FACADE =
        '/usr/lib/glibc-compat-libc.so.6'
    private static final List<String> SPLIT_FACADES = [
        '/usr/lib/glibc-compat-libpthread.so.0',
        '/usr/lib/glibc-compat-librt.so.1',
        '/usr/lib/glibc-compat-libm.so.6',
        '/usr/lib/glibc-compat-libdl.so.2',
        '/usr/lib/glibc-compat-libutil.so.1',
    ]

    def setupSpec() {
        harness.buildEnvironmentOutput(
            'create the link policy work directory',
            ['mkdir', '-p', WORK_DIRECTORY])
        harness.copyResourceToBuildEnvironment(
            'samples/downstream_compat_probe.c', "${WORK_DIRECTORY}/probe.c")
        harness.copyResourceToBuildEnvironment(
            'samples/executable-constructors.cpp',
            "${WORK_DIRECTORY}/probe.cpp")
        harness.copyResourceToBuildEnvironment(
            'samples/sanitizer_policy_CMakeLists.txt',
            "${WORK_DIRECTORY}/CMakeLists.txt")

        // Stand in for a derived image that fills the downstream extension
        // hook, the way php-minimal adds its php_pcre2_* stubs.
        harness.copyResourceToBuildEnvironment(
            'samples/downstream_compat_hook.c', "${WORK_DIRECTORY}/hook.c")
        harness.buildEnvironmentOutput(
            'compile the downstream compatibility hook',
            ['clang', '-fpie', '-O2', '-c', "${WORK_DIRECTORY}/hook.c",
             '-o', "${WORK_DIRECTORY}/hook.o"])
        harness.buildEnvironmentOutput(
            'install the downstream compatibility hook',
            ['llvm-ar', 'rcs', DOWNSTREAM_ARCHIVE,
             "${WORK_DIRECTORY}/hook.o"])
    }

    def cleanup() {
        harness.buildEnvironmentCommand(['rm', '-f', '/etc/musl-clang.conf'])
    }

    @Unroll
    def '#directory supplies libc without glibc_compat'() {
        when:
        Container.ExecResult link = linkProbe(
            'musl-clang', ['-fsanitize=address', "-L${directory}".toString()])
        String trace = linkerTrace(link)

        then:
        link.exitCode == 0
        trace.readLines().contains(LIBC_FACADE)
        SPLIT_FACADES.every { !trace.readLines().contains(it) }
        !trace.contains('libglibc_compat.a')

        where:
        directory << [ASAN_DIRECTORY, MSAN_DIRECTORY]
    }

    @Unroll
    def '#directory still supplies the downstream compatibility archive'() {
        when:
        Container.ExecResult link = linkProbe(
            'musl-clang', ['-fsanitize=address', "-L${directory}".toString()])

        then:
        link.exitCode == 0
        linkerTrace(link).contains(DOWNSTREAM_ARCHIVE)

        where:
        directory << [ASAN_DIRECTORY, MSAN_DIRECTORY]
    }

    @Unroll
    def '#sanitizer policy alone steers a #language wrapper link'() {
        given:
        installSanitizerPolicy(policy)

        when:
        // No -L: the declarative policy has to select the directory.
        Container.ExecResult link = linkProbe(driver, [])
        String trace = linkerTrace(link)

        then:
        link.exitCode == 0
        trace.readLines().contains(LIBC_FACADE)
        trace.contains(DOWNSTREAM_ARCHIVE)
        !trace.contains('libglibc_compat.a')
        language != 'C++' || trace.contains("${directory}/libc++.so")

        where:
        sanitizer | policy      | directory      | language | driver
        'ASan'    | ASAN_POLICY | ASAN_DIRECTORY | 'C'      | 'musl-clang'
        'ASan'    | ASAN_POLICY | ASAN_DIRECTORY | 'C++'    | 'musl-clang++'
        'MSan'    | MSAN_POLICY | MSAN_DIRECTORY | 'C'      | 'musl-clang'
        'MSan'    | MSAN_POLICY | MSAN_DIRECTORY | 'C++'    | 'musl-clang++'
    }

    @Unroll
    def '#sanitizer wrapper supports separate C++ compilation and linking'() {
        given:
        installSanitizerPolicy(policy)
        String suffix = UUID.randomUUID()
        String objectFile = "${WORK_DIRECTORY}/probe-${suffix}.o"
        String executable = "${WORK_DIRECTORY}/probe-${suffix}"

        when:
        Container.ExecResult compilation = harness.buildEnvironmentCommand([
            'musl-clang++', '-Werror', '-c',
            "${WORK_DIRECTORY}/probe.cpp".toString(), '-o', objectFile,
        ])
        Container.ExecResult link = harness.buildEnvironmentCommand([
            'musl-clang++', '-Werror', objectFile, '-o', executable,
        ])

        then:
        compilation.exitCode == 0
        link.exitCode == 0

        where:
        sanitizer | policy
        'ASan'    | ASAN_POLICY
        'MSan'    | MSAN_POLICY
    }

    @Unroll
    def '#sanitizer C wrapper links the C++ ABI only when requested'() {
        given:
        installSanitizerPolicy(policy)

        when:
        Container.ExecResult plainLink = linkProbe('musl-clang', [])
        Container.ExecResult cxxRuntimeLink = linkProbe(
            'musl-clang', ['-fsanitize-link-c++-runtime'])
        String plainTrace = linkerTrace(plainLink)
        String cxxRuntimeTrace = linkerTrace(cxxRuntimeLink)

        then:
        plainLink.exitCode == 0
        cxxRuntimeLink.exitCode == 0
        !plainTrace.contains("${directory}/libc++abi.so")
        cxxRuntimeTrace.contains("${directory}/libc++abi.so")
        !cxxRuntimeTrace.contains('/usr/lib/libc++abi.a')

        where:
        sanitizer | policy      | directory
        'ASan'    | ASAN_POLICY | ASAN_DIRECTORY
        'MSan'    | MSAN_POLICY | MSAN_DIRECTORY
    }

    def 'ASan C executable loads an instrumented C++ DSO'() {
        given:
        installSanitizerPolicy(ASAN_POLICY)
        List<String> sanitizerArguments = [
            '-O1', '-g', '-fsanitize=address,undefined,vptr',
            '-fno-sanitize=function',
        ]

        when:
        MuslSanitizerProgram program =
            harness.compileCWithCppSharedLibrary(
                'samples/sanitizer_cxx_dso_loader.c',
                'samples/sanitizer_cxx_dso.cpp',
                sanitizerArguments + ['-fsanitize-link-c++-runtime'],
                sanitizerArguments)
        Container.ExecResult result = harness.run(
            program, [], ['UBSAN_OPTIONS': 'halt_on_error=1'])

        then:
        result.exitCode == 0
        result.stdout.trim() == 'sanitizer-cxx-dso-ok'
        program.runtimeLibraries.keySet().containsAll(
            ['libc++.so.1', 'libc++abi.so.1', 'libunwind.so.1'])
    }

    @Unroll
    def '#sanitizer policy alone steers a #language CMake link'() {
        given:
        installSanitizerPolicy(policy)
        String buildDirectory =
            "${WORK_DIRECTORY}/cmake-${UUID.randomUUID()}"

        expect:
        harness.buildEnvironmentCommand([
            'cmake', '-S', WORK_DIRECTORY, '-B', buildDirectory,
            '-DCMAKE_TOOLCHAIN_FILE=/usr/local/share/musl/Toolchain.cmake',
            "-DPROBE_LANGUAGE=${language}".toString(),
        ]).exitCode == 0

        when:
        Container.ExecResult link = harness.buildEnvironmentCommand(
            ['cmake', '--build', buildDirectory, '--verbose'])
        String trace = linkerTrace(link)

        then:
        link.exitCode == 0
        trace.readLines().contains(LIBC_FACADE)
        trace.contains(DOWNSTREAM_ARCHIVE)
        !trace.contains('libglibc_compat.a')
        language != 'CXX' || trace.contains("${directory}/libc++.so")

        where:
        sanitizer | policy      | directory      | language
        'ASan'    | ASAN_POLICY | ASAN_DIRECTORY | 'C'
        'ASan'    | ASAN_POLICY | ASAN_DIRECTORY | 'CXX'
        'MSan'    | MSAN_POLICY | MSAN_DIRECTORY | 'C'
        'MSan'    | MSAN_POLICY | MSAN_DIRECTORY | 'CXX'
    }

    def 'links without a sanitizer policy keep the default libc entry'() {
        when:
        Container.ExecResult link = linkProbe('musl-clang', [])
        String trace = linkerTrace(link)

        then:
        link.exitCode == 0
        trace.contains(DOWNSTREAM_ARCHIVE)
        trace.readLines().contains(LIBC_FACADE)
    }

    private void installSanitizerPolicy(String policy) {
        harness.copyResourceToBuildEnvironment(
            policy, '/etc/musl-clang.conf')
    }

    private Container.ExecResult linkProbe(
        String driver, List<String> extraArguments) {
        List<String> command = [
            driver, "${WORK_DIRECTORY}/probe.c".toString(), '-Wl,-t',
        ]
        command.addAll(extraArguments)
        command.addAll(
            ['-o', "${WORK_DIRECTORY}/probe-${UUID.randomUUID()}".toString()])
        return harness.buildEnvironmentCommand(command)
    }

    private static String linkerTrace(Container.ExecResult link) {
        return "${link.stdout}\n${link.stderr}"
    }
}
