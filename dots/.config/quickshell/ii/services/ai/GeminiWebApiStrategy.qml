import QtQuick

ApiStrategy {
    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        let promptParts = [];

        if (systemPrompt && systemPrompt.trim().length > 0) {
            promptParts.push(`System instructions:\n${systemPrompt.trim()}`);
        }

        for (const message of messages) {
            const content = (message.rawContent || message.content || "").trim();
            if (content.length === 0)
                continue;

            const role = message.role === "assistant" ? "Assistant" : "User";
            promptParts.push(`${role}:\n${content}`);
        }

        promptParts.push("Assistant:");

        const result = {
            prompt: promptParts.join("\n\n---\n\n"),
            model: model.model
        };
        if (filePath && filePath.length > 0) {
            result.file_path = filePath;
        }
        return result;
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return "";
    }

    function stripInternalTags(text) {
        if (!text) return "";
        // Strip <FollowUp ... /> or unclosed <FollowUp ...>
        let cleaned = text.replace(/<FollowUp\b[^>]*\/?>/gi, "");
        cleaned = cleaned.replace(/<FollowUp\b[^>]*$/gi, "");
        return cleaned;
    }

    function parseResponseLine(line, message) {
        let cleanData = line.trim();
        if (!cleanData || cleanData.startsWith(":"))
            return {};

        if (cleanData.startsWith("data:"))
            cleanData = cleanData.slice(5).trim();

        if (!cleanData)
            return {};

        try {
            const dataJson = JSON.parse(cleanData);

            if (dataJson.error || dataJson.detail) {
                const errorMsg = `**Error**: ${dataJson.error || dataJson.detail}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            if (dataJson.text) {
                let chunkText = stripInternalTags(dataJson.text);
                message.rawContent += chunkText;
                message.content += chunkText;
            }
        } catch (e) {
            console.log("[AI] Gemini Web: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }

        return {};
    }

    function onRequestFinished(message) {
        if (!message.content || message.content.trim().length === 0) {
            const errorMsg = "⚠️ Could not reach Gemini server. Check that Google Chrome is logged into Gemini, or click ↻ to retry.";
            message.rawContent = errorMsg;
            message.content = errorMsg;
        } else {
            const cleaned = stripInternalTags(message.content);
            message.content = cleaned;
            message.rawContent = cleaned;
        }
        return { finished: true };
    }
}
