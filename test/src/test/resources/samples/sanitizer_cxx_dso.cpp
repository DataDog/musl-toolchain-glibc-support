#include <stdexcept>
#include <string>

extern "C" int
sanitizer_cxx_dso_run()
{
    try {
        throw std::runtime_error("instrumented C++ DSO");
    } catch (const std::exception &error) {
        return std::string(error.what()) == "instrumented C++ DSO" ? 42 : 1;
    }
}
