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
                message.rawContent += dataJson.text;
                message.content += dataJson.text;
            }
        } catch (e) {
            console.log("[AI] Gemini Web: Could not parse line: ", e);
            message.rawContent += line;
            message.content += line;
        }

        return {};
    }
}
