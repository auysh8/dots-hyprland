.pragma library

var colorsByArtId = ({});
var lastKnownColor = null;

function getColor(artId, fallbackColor) {
    if (artId && colorsByArtId[artId] !== undefined)
        return colorsByArtId[artId];

    if (lastKnownColor !== null)
        return lastKnownColor;

    return fallbackColor;
}

function setColor(artId, color) {
    if (!artId || color === undefined || color === null)
        return;

    colorsByArtId[artId] = color;
    lastKnownColor = color;
}
