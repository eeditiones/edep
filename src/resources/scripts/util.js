function createUUID() {
    // http://www.ietf.org/rfc/rfc4122.txt
    const s = [];
    const hexDigits = '0123456789abcdef';
    for (let i = 0; i < 36; i += 1) {
        s[i] = hexDigits.substr(Math.floor(Math.random() * 0x10), 1);
    }
    s[14] = '4'; // bits 12-15 of the time_hi_and_version field to 0010
    s[19] = hexDigits.substr((s[19] & 0x3) | 0x8, 1); // bits 6-7 of the clock_seq_hi_and_reserved to 01
    s[8] = s[13] = s[18] = s[23] = '-';

    const uuid = s.join('');
    return 'F' + uuid;
}

function expander(){
    const expander = document.querySelector('#expander');
    const details = document.querySelectorAll('details');

    if(expander.classList.contains('expanded')){
        Array.from(details).forEach(d => {
            d.removeAttribute('open');
            expander.classList.remove('expanded');
            expander.innerHTML = '&lt; &gt;';
        });
    }else{
        Array.from(details).forEach(d => {
            d.setAttribute('open','open');
            expander.classList.add('expanded');
            expander.innerHTML = '&gt; &lt;';
        });
    }

}
function checkDate(string) {
    if(string.length === 0 ) return true;// allow empty
    const val = new Date(string);
    if(val instanceof Date && !isNaN(val)) {
        return true;
    }
    return false;
}

window.addEventListener('DOMContentLoaded', () => {
    let language;
    let endpoint;

    const navLinks = Array.from(document.querySelectorAll('nav a'));
    navLinks.forEach(link => {
        link.addEventListener('click', e => {
            console.log('clicked it')

            navLinks.forEach(lk =>{
                lk.style.textDecoration = "none";
                lk.style.fontWeight = "300";
            })

            const parent = e.target.closest('a');
            parent.style.textDecoration = "underline";
            parent.style.fontWeight = "700";
        });
    });


    pbEvents.subscribe('pb-page-ready', null, (ev) => {
        language = ev.detail.language;
        endpoint = ev.detail.endpoint;
    });

    const fore = document.querySelector('fx-fore');
    fore.addEventListener('ready', () => {

        const epidoc = document.getElementById('transcriptionEditor');
        const output = document.getElementById('transcription-display');
    
        epidoc.addEventListener('update', (ev) => {
            fetch(`${endpoint}/api/render`, {
                method: 'POST',
                body: ev.detail.content.outerHTML,
                headers: {
                    "Content-Type": "application/xml"
                }
            })
            .then((response) => response.text())
            .then((html) => {
                output.innerHTML = html;
            });
        });


    });
});