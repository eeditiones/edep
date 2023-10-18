// Funtion to hide both the <pb-facsimile> element and the <pb-view> element binded to the <facsimile> elements of the source.
// The function looks for the elements <pb-facs-link> which are only created if a <facsimile> element exists in the source.

function hidePb() {
    const viewer = document.querySelector('pb-facsimile');
    const facs = document.getElementById('facs');
    const facsLinks = Array.from(facs.shadowRoot.querySelectorAll('pb-facs-link'));
    if (facsLinks.length === 0) {
        viewer.style.display = 'none';
        facs.style.display = 'none';
    }
}
// TODO: refactor function so as not to depend on a random wait
window.addEventListener('load', setTimeout(hidePb, 1500), false)