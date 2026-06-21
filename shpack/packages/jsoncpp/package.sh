# SPDX-License-Identifier: MIT

description "JsonCpp 1.9.7 -- C++ library for reading/writing JSON. Static" \
            "libjsoncpp only, built without cmake/meson."
homepage "https://github.com/open-source-parsers/jsoncpp"
license "MIT"

version 1.9.7 sha256=830bf352d822d8558e9d0eb19d640d2e38536b4b6699c30a4488da09d5b1df18 \
    url=https://github.com/open-source-parsers/jsoncpp/archive/1.9.7.tar.gz \
    fname=jsoncpp-1.9.7.tar.gz

build_system generic

depends_on compiler-wrapper gmake

install() {
    # -std=c++17 so the std::string_view Value overloads land in the archive;
    # cmake compiles at C++17 and references them.
    g++ -std=c++17 -fPIC -O2 -Iinclude -c \
        src/lib_json/json_reader.cpp \
        src/lib_json/json_value.cpp \
        src/lib_json/json_writer.cpp
    ar rcs libjsoncpp.a json_reader.o json_value.o json_writer.o
    mkdir -p "$PREFIX/lib" "$PREFIX/include"
    cp libjsoncpp.a "$PREFIX/lib/"
    cp -R include/json "$PREFIX/include/"
}
