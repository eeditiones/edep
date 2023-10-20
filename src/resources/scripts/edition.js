// Wrapper function
function prepareContents() {
(:   addPinPoint();:)
   hideFacsimile();
}

// Function to hide the element <pb-facsimile>
function hideFacsimile() {
    const viewer = document.querySelector('pb-facsimile');
    pbEvents.subscribe('pb-facsimile-status', null, (ev) => {
            if (ev.detail.status === 'fail') {
                viewer.style.display = 'none';
            } 
        });
}

// Function to add contents to the map
function addPinPoint() {
    pbEvents.subscribe('pb-page-ready', null, function () {
        const endpoint = document.querySelector("pb-page").getEndpoint();
        const path = document.querySelector("pb-document").getAttribute('path');
        const url = `${endpoint}/api/places/${path.replace("/", "%2F")}/findSpot`;
        console.log(`fetching places from: ${url}`);
        fetch(url).then(function (response) {
            return response.json();
        }).then(function (json) {
            pbEvents.emit("pb-update-map", "map", json);
           
        });
     /*   const pb = document.querySelector('#map-findSpot')
        const map = pb.shadowRoot.querySelector('#map')
        map.invalidateSize(); */
    })
}

window.addEventListener('WebComponentsReady', prepareContents, false)
