// The YAML reference parsers on the same files, for the bar AemiYAML is measured against (plan, section 6; phase 0).
//
//   c++ -O2 -std=c++17 yaml_references.cpp -o /tmp/yaml-references \
//     -I"$(brew --prefix rapidyaml)/include" -I"$(brew --prefix libfyaml)/include" -I"$(brew --prefix libyaml)/include" \
//     -L"$(brew --prefix rapidyaml)/lib" -L"$(brew --prefix libfyaml)/lib" -L"$(brew --prefix libyaml)/lib" -lryml -lfyaml -lyaml
//   /tmp/yaml-references ROUNDS FILE...
//
// Per library: CPU time of the process (CLOCK_PROCESS_CPUTIME_ID) and instructions retired (proc_pid_rusage, macOS), the best of
// ROUNDS passes over every file, as MB/s and instructions per byte. Files a library refuses are counted and left out of its figures.

// rapidyaml first: libfyaml includes <stdatomic.h>, which libc++ refuses before <atomic> below C++23.
#include <ryml.hpp>
#include <ryml_std.hpp>

#include <libfyaml.h>
#include <yaml.h>

#include <libproc.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#include <cstdio>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Sample {
    double seconds;
    unsigned long long instructions;
};

Sample now() {
    timespec time{};
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time);
    rusage_info_v4 usage{};
    proc_pid_rusage(getpid(), RUSAGE_INFO_V4, reinterpret_cast<rusage_info_t *>(&usage));
    return {time.tv_sec + time.tv_nsec / 1e9, usage.ri_instructions};
}

// libyaml's event stream: what Yams reads.
bool libyamlEvents(const std::string &text) {
    yaml_parser_t parser;
    yaml_parser_initialize(&parser);
    yaml_parser_set_input_string(&parser, reinterpret_cast<const unsigned char *>(text.data()), text.size());
    bool ok = true;
    for (;;) {
        yaml_event_t event;
        if (!yaml_parser_parse(&parser, &event)) { ok = false; break; }
        bool end = event.type == YAML_STREAM_END_EVENT;
        yaml_event_delete(&event);
        if (end) break;
    }
    yaml_parser_delete(&parser);
    return ok;
}

// libfyaml's event stream.
bool libfyamlEvents(const std::string &text) {
    fy_parse_cfg config{};
    config.flags = FYPCF_QUIET;
    fy_parser *parser = fy_parser_create(&config);
    if (!parser || fy_parser_set_string(parser, text.data(), text.size()) != 0) { fy_parser_destroy(parser); return false; }
    fy_event *event;
    while ((event = fy_parser_parse(parser)) != nullptr) fy_parser_event_free(parser, event);
    bool ok = !fy_parser_get_stream_error(parser);
    fy_parser_destroy(parser);
    return ok;
}

// libfyaml's document tree.
bool libfyamlTree(const std::string &text) {
    fy_parse_cfg config{};
    config.flags = FYPCF_QUIET;
    fy_document *document = fy_document_build_from_string(&config, text.data(), text.size());
    if (!document) return false;
    fy_document_destroy(document);
    return true;
}

// rapidyaml's tree, parsed in place in a copy (its fastest documented path).
bool rapidyamlTree(const std::string &text) {
    static bool quiet = [] {
        ryml::Callbacks callbacks;
        callbacks.set_error_basic([](ryml::csubstr, const ryml::ErrorDataBasic &, void *) { throw std::runtime_error("ryml"); });
        callbacks.set_error_parse([](ryml::csubstr, const ryml::ErrorDataParse &, void *) { throw std::runtime_error("ryml"); });
        callbacks.set_error_visit([](ryml::csubstr, const ryml::ErrorDataVisit &, void *) { throw std::runtime_error("ryml"); });
        ryml::set_callbacks(callbacks);
        return true;
    }();
    (void)quiet;
    std::string copy = text;
    try {
        ryml::Tree tree = ryml::parse_in_place(ryml::substr(copy.data(), copy.size()));
        return tree.size() > 0;
    } catch (...) {
        return false;
    }
}

}  // namespace

int main(int argc, char **argv) {
    if (argc < 3) { std::fprintf(stderr, "usage: %s ROUNDS FILE...\n", argv[0]); return 2; }
    int rounds = std::atoi(argv[1]);
    std::vector<std::string> texts;
    for (int i = 2; i < argc; ++i) {
        std::ifstream file(argv[i], std::ios::binary);
        std::stringstream buffer;
        buffer << file.rdbuf();
        texts.push_back(buffer.str());
    }
    struct Library { const char *name; std::function<bool(const std::string &)> parse; };
    std::vector<Library> libraries = {
        {"libyaml 0.2.5 events", libyamlEvents},
        {"libfyaml 0.9.6 events", libfyamlEvents},
        {"libfyaml 0.9.6 tree", libfyamlTree},
        {"rapidyaml 0.16.0 tree", rapidyamlTree},
    };
    std::printf("| library | files read | refused | MB/s | instructions/byte |\n|---|---|---|---|---|\n");
    for (const auto &library : libraries) {
        std::vector<bool> accepted;
        size_t bytes = 0, refused = 0;
        for (const auto &text : texts) {
            bool ok = library.parse(text);
            accepted.push_back(ok);
            if (ok) bytes += text.size(); else ++refused;
        }
        double bestSeconds = 1e30;
        unsigned long long bestInstructions = ~0ULL;
        for (int round = 0; round < rounds; ++round) {
            Sample start = now();
            for (size_t i = 0; i < texts.size(); ++i) if (accepted[i]) library.parse(texts[i]);
            Sample end = now();
            if (end.seconds - start.seconds < bestSeconds) {
                bestSeconds = end.seconds - start.seconds;
                bestInstructions = end.instructions - start.instructions;
            }
        }
        std::printf("| %s | %zu | %zu | %.0f | %.1f |\n", library.name, texts.size() - refused, refused,
                    bytes / bestSeconds / 1e6, double(bestInstructions) / double(bytes));
    }
    return 0;
}
