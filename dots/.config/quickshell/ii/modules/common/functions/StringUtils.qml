pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Formats a string according to the args that are passed inc
     * @param { string } str
     * @param  {...any} args
     * @returns { string }
     */
    function format(str, ...args) {
        return str.replace(/{(\d+)}/g, (match, index) => typeof args[index] !== 'undefined' ? args[index] : match);
    }

    /**
     * Returns the domain of the passed in url or null
     * @param { string } url
     * @returns { string| null }
     */
    function getDomain(url) {
        const match = url.match(/^(?:https?:\/\/)?(?:www\.)?([^\/]+)/);
        return match ? match[1] : null;
    }

    /**
     * Returns the base url of the passed in url or null
     * @param { string } url
     * @returns { string | null }
     */
    function getBaseUrl(url) {
        const match = url.match(/^(https?:\/\/[^\/]+)(\/.*)?$/);
        return match ? match[1] : null;
    }

    /**
     * Escapes single quotes in shell commands
     * @param { string } str
     * @returns { string }
     */
    function shellSingleQuoteEscape(str) {
        return String(str)
        // .replace(/\\/g, '\\\\')
        .replace(/'/g, "'\\''");
    }

    /**
     * Splits markdown blocks into three different types: text, think, and code.
     * @param { string } markdown
     * @returns {Array<{type: "text" | "think" | "code", content: string, lang?: string, completed?: boolean}>}
     */
    function splitMarkdownBlocks(markdown) {
        const regex = /```[ \t]*([^\r\n`]*)[ \t]*(?:\r?\n)([\s\S]*?)(?:^|\r?\n)```[ \t]*(?=\r?\n|$)|<think>([\s\S]*?)<\/think>/gm;
        /**
         * @type {{type: "text" | "think" | "code"; content: string; lang: string | undefined; completed: boolean | undefined}[]}
         */
        let result = [];
        let lastIndex = 0;
        let match;
        while ((match = regex.exec(markdown)) !== null) {
            if (match.index > lastIndex) {
                const text = markdown.slice(lastIndex, match.index);
                if (text.trim()) {
                    result.push({
                        type: "text",
                        content: text
                    });
                }
            }
            if (match[0].startsWith('```')) {
                if (match[2] && match[2].trim()) {
                    const lang = (match[1] || "").trim().split(/\s+/)[0];
                    result.push({
                        type: "code",
                        lang: lang,
                        content: match[2],
                        completed: true
                    });
                }
            } else if (match[0].startsWith('<think>')) {
                if (match[3] && match[3].trim()) {
                    result.push({
                        type: "think",
                        content: match[3],
                        completed: true
                    });
                }
            }
            lastIndex = regex.lastIndex;
        }
        // Handle any remaining text after the last match
        if (lastIndex < markdown.length) {
            const text = markdown.slice(lastIndex);
            // Check for unfinished <think> block
            const thinkStart = text.indexOf('<think>');
            const codeStart = text.indexOf('```');
            if (thinkStart !== -1 && (codeStart === -1 || thinkStart < codeStart)) {
                const beforeThink = text.slice(0, thinkStart);
                if (beforeThink.trim()) {
                    result.push({
                        type: "text",
                        content: beforeThink
                    });
                }
                const thinkContent = text.slice(thinkStart + 7);
                if (thinkContent.trim()) {
                    result.push({
                        type: "think",
                        content: thinkContent,
                        completed: false
                    });
                }
            } else if (codeStart !== -1) {
                const beforeCode = text.slice(0, codeStart);
                if (beforeCode.trim()) {
                    result.push({
                        type: "text",
                        content: beforeCode
                    });
                }
                // Try to detect language after ```
                const codeLangMatch = text.slice(codeStart + 3).match(/^[ \t]*([^\r\n`]*)[ \t]*(?:\r?\n)/);
                let lang = "";
                let codeContentStart = codeStart + 3;
                if (codeLangMatch) {
                    lang = (codeLangMatch[1] || "").trim().split(/\s+/)[0];
                    codeContentStart += codeLangMatch[0].length;
                } else if (text[codeStart + 3] === '\n' || (text[codeStart + 3] === '\r' && text[codeStart + 4] === '\n')) {
                    codeContentStart += 1;
                    if (text[codeStart + 3] === '\r')
                        codeContentStart += 1;
                }
                const codeRemainder = text.slice(codeContentStart);
                const repeatedFenceRegex = /(?:^|\r?\n)```[ \t]*([^\r\n`]*)[ \t]*(?:\r?\n)/g;
                let repeatedFenceMatch;
                while ((repeatedFenceMatch = repeatedFenceRegex.exec(codeRemainder)) !== null) {
                    const repeatedLang = (repeatedFenceMatch[1] || "").trim().split(/\s+/)[0];
                    if (repeatedLang) {
                        lang = repeatedLang;
                        codeContentStart += repeatedFenceMatch.index + repeatedFenceMatch[0].length;
                    }
                }
                const codeContent = text.slice(codeContentStart);
                if (codeContent.trim()) {
                    result.push({
                        type: "code",
                        lang,
                        content: codeContent,
                        completed: false
                    });
                }
            } else if (text.trim()) {
                result.push({
                    type: "text",
                    content: text
                });
            }
        }
        // console.log(JSON.stringify(result, null, 2));
        return result;
    }

    /**
     * Returns the original string with backslashes escaped
     * @param { string } str
     * @returns { string }
     */
    function escapeBackslashes(str) {
        return str.replace(/\\/g, '\\\\');
    }

    /**
     * Wraps words to supplied maximum length
     * @param { string | null } str
     * @param { number } maxLen
     * @returns { string }
     */
    function wordWrap(str, maxLen) {
        if (!str)
            return "";
        let words = str.split(" ");
        let lines = [];
        let current = "";
        for (let i = 0; i < words.length; ++i) {
            if ((current + (current.length > 0 ? " " : "") + words[i]).length > maxLen) {
                if (current.length > 0)
                    lines.push(current);
                current = words[i];
            } else {
                current += (current.length > 0 ? " " : "") + words[i];
            }
        }
        if (current.length > 0)
            lines.push(current);
        return lines.join("\n");
    }

    /**
     * Cleans up a music title by removing bracketed and special characters.
     * @param { string } title
     * @returns { string }
     */
    function cleanMusicTitle(title) {
        if (!title)
            return "";
        // Brackets
        title = title.replace(/^ *\([^)]*\) */g, " "); // Round brackets
        title = title.replace(/^ *\[[^\]]*\] */g, " "); // Square brackets
        title = title.replace(/^ *\{[^\}]*\} */g, " "); // Curly brackets
        // Japenis brackets
        title = title.replace(/^ *【[^】]*】/, ""); // Touhou
        title = title.replace(/^ *《[^》]*》/, ""); // ??
        title = title.replace(/^ *「[^」]*」/, ""); // OP/ED thingie
        title = title.replace(/^ *『[^』]*』/, ""); // OP/ED thingie

        return title.trim();
    }

    /**
     * Converts seconds to a friendly time string (e.g. 1:23 or 1:02:03).
     * @param { number } seconds
     * @returns { string }
     */
    function friendlyTimeForSeconds(seconds) {
        if (isNaN(seconds) || seconds < 0)
            return "0:00";
        seconds = Math.floor(seconds);
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (h > 0) {
            return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
        } else {
            return `${m}:${s.toString().padStart(2, '0')}`;
        }
    }

    /**
     * Escapes HTML special characters in a string.
     * @param { string } str
     * @returns { string }
     */
    function escapeHtml(str) {
        if (typeof str !== 'string')
            return str;
        return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    /**
     * Cleans a cliphist entry by removing leading digits and tab.
     * @param { string } str
     * @returns { string }
     */
    function cleanCliphistEntry(str: string): string {
        return str.replace(/^\d+\t/, "");
    }

    /**
     * Checks if any substring in the list is contained in the string.
     * @param { string } str
     * @param { string[] } substrings
     * @returns { boolean }
     */
    function stringListContainsSubstring(str, substrings) {
        for (let i = 0; i < substrings.length; ++i) {
            if (str.includes(substrings[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * Removes the given prefix from the string if present.
     * @param { string } str
     * @param { string } prefix
     * @returns { string }
     */
    function cleanPrefix(str, prefix) {
        if (str.startsWith(prefix)) {
            return str.slice(prefix.length);
        }
        return str;
    }

    /**
     * Removes the first matching prefix from the string if present.
     * @param { string } str
     * @param { string[] } prefixes
     * @returns { string }
     */
    function cleanOnePrefix(str, prefixes) {
        for (let i = 0; i < prefixes.length; ++i) {
            if (str.startsWith(prefixes[i])) {
                return str.slice(prefixes[i].length);
            }
        }
        return str;
    }

    function toTitleCase(str) {
        // Replace "-" and "_" with space, then capitalize each word
        return str.replace(/[-_]/g, " ").replace(
            /\w\S*/g,
            function(txt) {
            return txt.charAt(0).toUpperCase() + txt.substr(1).toLowerCase();
            }
        );
    }

    /**
     * High-accuracy weighted code language sniffer.
     * Analyzes signatures, syntax tokens, and negative discriminators to determine the programming language.
     * Returns a valid KSyntaxHighlighting definition name or "plaintext".
     *
     * @param { string } code
     * @returns { string }
     */
    function detectLanguage(code) {
        if (!code || typeof code !== "string")
            return "plaintext";
        const trimmed = code.trim();
        if (trimmed.length === 0)
            return "plaintext";

        // 1. JSON check (fast and exact)
        if ((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))) {
            try {
                JSON.parse(trimmed);
                if (trimmed.includes(":") && trimmed.includes('"')) {
                    return "json";
                }
            } catch (e) {}
        }

        const scores = {
            python: 0,
            javascript: 0,
            bash: 0,
            c: 0,
            cpp: 0,
            rust: 0,
            go: 0,
            java: 0,
            kotlin: 0,
            ruby: 0,
            swift: 0,
            cs: 0,
            lua: 0,
            html: 0,
            css: 0,
            sql: 0,
            qml: 0
        };

        // Go signatures
        if (/^\s*package\s+\w+/m.test(code)) scores.go += 8;
        if (/^\s*import\s+(?:\([^\)]+\)|"[^"]+")/m.test(code)) scores.go += 6;
        if (/\bfunc\s+(?:\(\s*\w+\s+\*?\w+\s*\)\s*)?\w+\s*\(/.test(code)) scores.go += 8;
        if (/:=/.test(code)) scores.go += 5;
        if (/\bfmt\.(?:Println|Printf|Sprintf|Print|Errorf)\s*\(/.test(code)) scores.go += 8;
        if (/\b(?:chan|defer|go)\s+\w+/.test(code)) scores.go += 5;
        // Go penalties
        if (/\b(?:class|function)\b/.test(code)) scores.go -= 8;

        // Python signatures
        if (/^\s*def\s+\w+\s*\(.*\)\s*:/m.test(code)) scores.python += 5;
        if (/^\s*elif\s+.*:/m.test(code)) scores.python += 4;
        if (/if\s+__name__\s*==\s*['"]__main__['"]\s*:/.test(code)) scores.python += 6;
        if (/\bself\.\w+/.test(code)) scores.python += 3;
        if (/\b(None|True|False)\b/.test(code)) scores.python += 2;
        if (/^\s*import\s+[\w\.]+(?:\s+as\s+\w+)?\s*$/m.test(code)) scores.python += 3;
        if (/^\s*from\s+[\w\.]+\s+import\s+/m.test(code) && !/from\s+['"]/.test(code)) scores.python += 4;
        if (/\bprint\s*\(/.test(code)) scores.python += 2;
        if (/^\s*except\s+(?:\w+\s+as\s+\w+|\w+)\s*:/m.test(code)) scores.python += 4;
        if (/f['"][^"']*\{[^"']+\}[^"']*['"]/.test(code)) scores.python += 4;
        // Python penalties
        if (/\b(const|let|var|function)\b/.test(code)) scores.python -= 8;
        if (/===|!==|=>|:=/.test(code)) scores.python -= 8;
        if (/\}\s*$/m.test(code)) scores.python -= 3;

        // JavaScript / TypeScript signatures
        if (/\b(const|let|var)\s+\w+\s*=/.test(code)) scores.javascript += 4;
        if (/\bconsole\.(log|error|warn|info|debug)\s*\(/.test(code)) scores.javascript += 5;
        if (/=>/.test(code)) scores.javascript += 3;
        if (/\bfunction\s*\w*\s*\(.*\)\s*\{/.test(code)) scores.javascript += 4;
        if (/===|!==/.test(code)) scores.javascript += 4;
        if (/import\s+.*from\s+['"]/.test(code)) scores.javascript += 5;
        if (/export\s+(?:default|const|function|class)/.test(code)) scores.javascript += 4;
        if (/\b(null|undefined)\b/.test(code)) scores.javascript += 2;
        if (/\b(document\.|window\.|process\.env)/.test(code)) scores.javascript += 4;
        // JS penalties
        if (/^\s*def\s+\w+/m.test(code)) scores.javascript -= 8;
        if (/^\s*elif\s+/m.test(code)) scores.javascript -= 8;

        // Bash / Shell signatures
        if (/^#!\s*\/(?:usr\/)?bin\/(?:env\s+)?(?:bash|sh|zsh)/m.test(code)) scores.bash += 8;
        if (/\b(sudo|apt|pacman|dnf|chmod|chown|mkdir|touch|curl|wget|systemctl|grep|cat|echo)\s+/.test(code)) scores.bash += 3;
        if (/\$\([^\)]+\)|\$\{[^\}]+\}/.test(code)) scores.bash += 3;
        if (/\b(fi|done|esac)\s*$/m.test(code)) scores.bash += 5;
        if (/\|\s*(?:grep|awk|sed|xargs|cut|sort|uniq|head|tail)\b/.test(code)) scores.bash += 4;
        if (/2>&1|>>\s*\/dev\/null/.test(code)) scores.bash += 4;

        // Rust signatures
        if (/\bfn\s+\w+\s*\(.*\)/.test(code)) scores.rust += 4;
        if (/\blet\s+mut\s+\w+/.test(code)) scores.rust += 5;
        if (/\b(println!|format!|vec!|panic!|eprintln!)\s*\(/.test(code)) scores.rust += 5;
        if (/\bimpl\s+(?:\w+\s+for\s+)?\w+/.test(code)) scores.rust += 4;
        if (/\bpub\s+(?:fn|struct|enum|trait|mod)\b/.test(code)) scores.rust += 4;
        if (/->\s*(?:Result|Option|Self|\w+<.*>)\s*\{/.test(code)) scores.rust += 4;

        // Java signatures
        if (/\bpublic\s+(?:static\s+)?(?:void|class|interface)\b/.test(code)) scores.java += 7;
        if (/\bSystem\.(?:out|err)\.(?:print|println)\s*\(/.test(code)) scores.java += 8;
        if (/^\s*package\s+[\w\.]+;/m.test(code)) scores.java += 7;
        if (/\bpublic\s+static\s+void\s+main\s*\(/.test(code)) scores.java += 10;

        // Kotlin signatures
        if (/\bfun\s+\w+\s*\(.*\)/.test(code)) scores.kotlin += 8;
        if (/\bval\s+\w+\s*[:=]|\bvar\s+\w+\s*[:=]/.test(code)) scores.kotlin += 5;
        if (/\bcompanion\s+object\b|\bdata\s+class\b/.test(code)) scores.kotlin += 7;

        // C# signatures
        if (/\busing\s+System(?:\.[\w\.]+)?;/.test(code)) scores.cs += 9;
        if (/\bConsole\.(?:WriteLine|Write)\s*\(/.test(code)) scores.cs += 8;

        // Swift signatures
        if (/\bfunc\s+\w+\s*\(.*\)\s*->/.test(code)) scores.swift += 8;
        if (/\bimport\s+(?:UIKit|Foundation|SwiftUI)\b/.test(code)) scores.swift += 9;
        if (/\bguard\s+let\b/.test(code)) scores.swift += 8;

        // Ruby signatures
        if (/\bdef\s+\w+[!\?]?\s*(?:\([^\)]*\)|\s|$)/.test(code)) scores.ruby += 4;
        if (/\b(?:attr_accessor|attr_reader)\b/.test(code)) scores.ruby += 8;

        // Lua signatures
        if (/\blocal\s+\w+\s*=/.test(code)) scores.lua += 6;
        if (/~=/.test(code)) scores.lua += 5;

        // C / C++ signatures
        let isCpp = false;
        if (/#include\s*<iostream>|std::|\b(?:cout|cin|cerr)\s*<<|\bnullptr\b|\bclass\s+\w+\s*\{|\btemplate\s*<|namespace\s+\w+/.test(code)) {
            scores.cpp += 8;
            isCpp = true;
        }
        if (/#include\s*<[\w\.\/]+>/.test(code)) {
            if (/#include\s*<stdio|stdlib|string\.h|math\.h|unistd\.h|time\.h>/.test(code)) {
                scores.c += 7;
            } else if (!isCpp) {
                scores.c += 4;
                scores.cpp += 4;
            }
        }
        if (/\bint\s+main\s*\(\s*(?:void|int\s+argc|\))/.test(code)) {
            if (isCpp) scores.cpp += 5;
            else scores.c += 5;
        }
        if (/\b(?:printf|scanf)\s*\(/.test(code)) {
            scores.c += 6;
        }
        if (/#pragma\s+once/.test(code)) {
            if (isCpp) scores.cpp += 4;
            else scores.c += 4;
        }

        // HTML / XML signatures
        if (/<!DOCTYPE\s+html>/i.test(code)) scores.html += 7;
        if (/<\/?(?:html|head|body|div|span|p|a|input|button|table|tr|td|ul|li|form|h[1-6])[\s>]/i.test(code)) scores.html += 5;
        if (/<\/\w+>/.test(code)) scores.html += 3;

        // CSS signatures
        if (/[\.\#\w\-]+\s*\{[\s\S]*?(?:color|margin|padding|background|display|flex|font-size|border)\s*:/.test(code)) scores.css += 5;
        if (/@media\s*\(/.test(code)) scores.css += 5;

        // SQL signatures
        if (/\bSELECT\s+[\s\S]+?\s+FROM\b/i.test(code)) scores.sql += 5;
        if (/\b(?:INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b/i.test(code)) scores.sql += 5;
        if (/\b(?:CREATE|ALTER|DROP)\s+TABLE\b/i.test(code)) scores.sql += 5;

        // QML signatures
        if (/import\s+QtQuick/.test(code)) scores.qml += 6;
        if (/property\s+(?:int|string|bool|real|var|color)\s+\w+/.test(code)) scores.qml += 5;

        let bestLang = "";
        let bestScore = 0;
        for (const lang in scores) {
            if (scores[lang] > bestScore) {
                bestScore = scores[lang];
                bestLang = lang;
            }
        }

        // Require confidence score of at least 3 to classify as code
        return (bestScore >= 3) ? bestLang : "plaintext";
    }
}
