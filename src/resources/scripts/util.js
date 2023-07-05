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

    pbEvents.subscribe('pb-page-ready', null, (ev) => {
        language = ev.detail.language;
    });
    pbEvents.subscribe('pb-i18n-update', null, (ev) => {
        const lang = ev.detail.language;
        const twoletter = lang.length !== 2 ? lang.substring(lang, 0, 2) : lang;
        document.dispatchEvent(new CustomEvent('fx-language', {
            detail: { language: twoletter },
            bubbles: true,
            composed: true
        }));
    });

    const fore = document.querySelector('fx-fore');
    fore.addEventListener('ready', () => {
        pbEvents.emit('pb-i18n-language', null, { language });

        const epidoc = document.getElementById('transcriptionEditor');
        const output = document.getElementById('transcription-display');
    
        epidoc.addEventListener('update', (ev) => {
            fetch('api/render', {
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
    });
});