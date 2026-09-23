#include <iostream>
#include <locale>
#include <sstream>

#if !_LIBCPP_INSTRUMENTED_WITH_ASAN
#  error "ASan C++ builds require the matching libc++ headers"
#endif

int main() {
    std::istringstream input(std::string{"21"});
    int value = 0;
    input >> value;
    if (value != 21) {
        return 1;
    }
    std::cout.imbue(std::locale::classic());
    std::cout << "asan-ubsan-cxx-standard-library-ok\n";
}
