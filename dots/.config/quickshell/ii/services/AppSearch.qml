pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQml

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

	// Cached deduplicated list to avoid rebuilding on every access
	property list<DesktopEntry> list: []

	Timer {
		id: rebuildDebounceTimer
		interval: 300
		repeat: false
		onTriggered: rebuild()
	}

	Connections {
	    target: DesktopEntries

		function onApplicationsChanged() {
		    rebuildDebounceTimer.restart();
		}
	}

	Component.onCompleted: {
	    rebuild();
	}

	// Deduplicate entries by id to prevent duplicate icons
	function rebuild() {
	    const apps = Array.from(DesktopEntries.applications?.values ?? []);
	    const seen = new Set();

	    list = apps.filter(app => {
	        if (!app || !app.id || seen.has(app.id))
	            return false;

	        seen.add(app.id);
	        return true;
	    });
	}
    
    readonly property var preppedTargets: list.map(a => {
        const nameStr = a.name || "";
        const idStr = a.id || "";
        const genericStr = a.genericName || "";
        const commentStr = a.comment || "";
        const kwStr = Array.isArray(a.keywords) ? a.keywords.join(" ") : "";
        const execStr = Array.isArray(a.command) ? a.command.join(" ") : "";
        const searchBlob = `${nameStr} ${idStr} ${genericStr} ${kwStr} ${commentStr} ${execStr}`;
        return {
            name: Fuzzy.prepare(`${nameStr} `),
            all: Fuzzy.prepare(`${searchBlob} `),
            entry: a
        };
    })

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))

    function fuzzyQuery(search: string): var {
        if (!search || search.trim().length === 0) return [];
        if (root.list.length === 0) rebuild();

        if (root.sloppySearch) {
            return root.levenshteinQuery(search);
        }

        const cleanQuery = search.trim();

        // 1. Primary: Match by application name
        const nameResults = Fuzzy.go(cleanQuery, preppedTargets, {
            key: "name",
            threshold: -10000
        }).map(r => r.obj.entry);

        // 2. Secondary: Match by keywords, generic name, desktop ID, or command
        const seen = new Set(nameResults.map(e => e.id));
        const allResults = Fuzzy.go(cleanQuery, preppedTargets, {
            key: "all",
            threshold: -10000
        }).map(r => r.obj.entry).filter(e => {
            if (seen.has(e.id)) return false;
            seen.add(e.id);
            return true;
        });

        // 3. Fallback: Substring match across all desktop entries if fuzzy yielded nothing
        let fallbackResults = [];
        if (nameResults.length === 0 && allResults.length === 0) {
            const lower = cleanQuery.toLowerCase();
            fallbackResults = root.list.filter(app => {
                const n = (app.name || "").toLowerCase();
                const id = (app.id || "").toLowerCase();
                const g = (app.genericName || "").toLowerCase();
                const cmd = (app.command || []).join(" ").toLowerCase();
                return n.includes(lower) || id.includes(lower) || g.includes(lower) || cmd.includes(lower);
            });
        }

        return [...nameResults, ...allResults, ...fallbackResults];
    }

    function levenshteinQuery(search: string): var {
        const prepared = BitwiseFuzzy.prepare(search);
        return BitwiseFuzzy.search(prepared, list, { key: "name", threshold: root.scoreThreshold });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = DesktopEntries.byId(str);
        if (entry) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = DesktopEntries.heuristicLookup(str);
        if (heuristicEntry) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
