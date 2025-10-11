/* ======================  ZOTERO AUTOCOMPLETE WEB COMPONENT  ====================== */
class ZoteroAutocomplete extends HTMLElement {
    static get observedAttributes() {
        return ['endpoint', 'bib-endpoint', 'tag', 'limit', 'minlength', 'debounce'];
    }

    constructor() {
        super();
        // state
        this._items = [];
        this._active = -1;
        this._selected = null;
        this._debounceMs = 250;
        this._minlen = 2;
        this._uidBase = this._uid();

        // markup (light DOM)
        this.classList.add('za');
        if (!this.querySelector('input')) {
            this.innerHTML = `
        <div class="za-field" style="position:relative;display:block;">
          <input class="za-input" type="text" autocomplete="off" aria-autocomplete="list"
                 aria-expanded="false" aria-controls="za-list-${this._uidBase}"
                 placeholder="Search references…" />
          <button type="button" class="za-clear" aria-label="Clear" title="Clear"
                  style="position:absolute;right:.5rem;top:50%;transform:translateY(-50%);
                         border:0;background:transparent;cursor:pointer;font-size:18px;
                         line-height:1;color:#888;display:none;">×</button>
        </div>
        <ul class="za-list" id="za-list-${this._uidBase}" role="listbox"
            style="list-style:none;margin:.25rem 0 0;padding:.25rem;border:1px solid #ddd;border-radius:.5rem;
                   box-shadow:0 4px 14px rgba(0,0,0,.08);max-height:320px;overflow:auto;display:none;
                   background:#fff;position:relative;z-index:1;"></ul>
      `;
        }

        this.$input = this.querySelector('.za-input') || this.querySelector('input');
        this.$clear = this.querySelector('.za-clear');
        this.$list = this.querySelector('.za-list');

        // bind handlers
        this._onInput = this._debounce(this._handleInput.bind(this), this._debounceMs);
        this._onKeyInput = this._handleKeyOnInput.bind(this);
        this._onKeyItem = this._handleKeyOnItem.bind(this);
        this._onClick = this._handleClick.bind(this);
        this._onBlur = this._handleBlur.bind(this);
        this._onFocus = this._handleFocus.bind(this);
        this._onClear = this._handleClear.bind(this);
    }

    connectedCallback() {
        // configuration
        this._endpoint = this.getAttribute('endpoint') || '/api/zotero/items/suggest';
        this._bibEndpoint = this.getAttribute('bib-endpoint') || '/api/zotero/items/bib';
        this._tag = this.getAttribute('tag') || '';
        this._limit = parseInt(this.getAttribute('limit') || '8', 10);
        this._minlen = parseInt(this.getAttribute('minlength') || String(this._minlen), 10);
        this._debounceMs = parseInt(this.getAttribute('debounce') || String(this._debounceMs), 10);

        // rebind debounce with current ms
        this.$input.removeEventListener('input', this._onInput);
        this._onInput = this._debounce(this._handleInput.bind(this), this._debounceMs);

        // events
        this.$input.addEventListener('input', this._onInput);
        this.$input.addEventListener('keydown', this._onKeyInput);
        this.$list.addEventListener('mousedown', this._onClick); // mousedown avoids blur before click
        this.$list.addEventListener('keydown', this._onKeyItem);
        this.addEventListener('focusout', this._onBlur);
        this.addEventListener('focusin', this._onFocus);
        this.$clear.addEventListener('click', this._onClear);

        // default look (easily overridden by page CSS)
        const baseFont = '16px/1.35 system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif';
        this.$input.style.cssText = [
            `font:${baseFont}`,
            'padding:.75rem 2rem .75rem 1rem',
            'border:1px solid #ccc',
            'border-radius:.75rem',
            'width:100%',
            'box-sizing:border-box',
            'outline:none',
            'transition:border-color .15s ease',
            'background:#fff',
        ].join(';');
        this.$input.addEventListener('focus', () => (this.$input.style.borderColor = '#888'));
        this.$input.addEventListener('blur', () => (this.$input.style.borderColor = '#ccc'));
    }

    disconnectedCallback() {
        this.$input.removeEventListener('input', this._onInput);
        this.$input.removeEventListener('keydown', this._onKeyInput);
        this.$list.removeEventListener('mousedown', this._onClick);
        this.$list.removeEventListener('keydown', this._onKeyItem);
        this.removeEventListener('focusout', this._onBlur);
        this.removeEventListener('focusin', this._onFocus);
        this.$clear.removeEventListener('click', this._onClear);
    }

    attributeChangedCallback(name, _old, value) {
        if (!this.isConnected) return;
        if (name === 'endpoint') this._endpoint = value || this._endpoint;
        if (name === 'bib-endpoint') this._bibEndpoint = value || this._bibEndpoint;
        if (name === 'tag') this._tag = value || '';
        if (name === 'limit') this._limit = parseInt(value || '8', 10);
        if (name === 'minlength') this._minlen = parseInt(value || '2', 10);
        if (name === 'debounce') {
            this._debounceMs = parseInt(value || '250', 10);
            this.$input?.removeEventListener('input', this._onInput);
            this._onInput = this._debounce(this._handleInput.bind(this), this._debounceMs);
            this.$input?.addEventListener('input', this._onInput);
        }
    }

    /* ---------------------------- public API ---------------------------- */
    get value() {
        return this._selected?.key || '';
    }
    get selected() {
        return this._selected || null;
    }
    clear() {
        this.$input.value = '';
        this.$input.dataset.key = '';
        this._selected = null;
        this._render([]);
        this._toggleClear();
    }

    /* ---------------------------- internals ---------------------------- */
    async _handleInput(e) {
        const q = e.target.value.trim();
        this._selected = null;
        this._toggleClear();
        if (q.length < this._minlen) return this._render([]);

        try {
            const url = new URL(this._endpoint, window.location.href);
            url.searchParams.set('q', q);
            if (this._tag) url.searchParams.set('tag', this._tag);
            if (this._limit) url.searchParams.set('limit', String(this._limit));
            const res = await fetch(url.toString(), { credentials: 'include' });
            if (!res.ok) throw new Error('HTTP ' + res.status);
            let data = await res.json();
            const items = Array.isArray(data) ? data : data.items || [];
            // Normalize to { key, title, bib? }
            let list = items
                .map(it => ({
                    key: it.key || it.data?.key || '',
                    title: it.title || it.data?.title || '',
                    bib: it.bib || it.html || '',
                }))
                .filter(x => x.key);

            // If endpoint didn’t include bib/html, fetch per-item (limited)
            if (list.length && !list[0].bib) {
                const limited = list.slice(0, this._limit);
                const htmls = await Promise.all(limited.map(i => this._fetchBib(i.key).catch(() => '')));
                limited.forEach((i, idx) => (i.bib = htmls[idx] || this._escape(i.title || '[untitled]')));
                list = limited;
            }

            this._render(list);
        } catch (err) {
            console.error('[zotero-autocomplete] suggest error:', err);
            this._render([]);
        }
    }

    async _fetchBib(key) {
        const url = new URL(this._bibEndpoint, window.location.href);
        url.searchParams.set('key', key);
        const res = await fetch(url.toString(), { credentials: 'include' });
        if (!res.ok) throw new Error('HTTP ' + res.status);
        return await res.text(); // HTML snippet
    }

    _render(items) {
        // build list
        this._items = items;
        this._active = -1;
        this.$list.innerHTML = '';
        if (!items.length) {
            this.$list.style.display = 'none';
            this.$input.setAttribute('aria-expanded', 'false');
            return;
        }

        items.forEach((it, idx) => {
            const id = `${this._uidBase}-opt-${idx}`;
            const li = document.createElement('li');
            li.className = 'za-item';
            li.id = id;
            li.setAttribute('role', 'option');
            li.setAttribute('data-idx', String(idx));
            li.setAttribute('data-key', it.key);
            li.tabIndex = -1; // focusable via JS/Tab sequence
            li.style.cssText = 'padding:.5rem .75rem;border-radius:.5rem;margin:.15rem 0;cursor:pointer;outline:none;';
            // bib is HTML from our API; fallback is escaped title
            li.innerHTML = `
        <div class="za-bib" style="font:14px/1.35 system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
          ${it.bib || this._escape(it.title || '[untitled]')}
        </div>
      `;
            // Mouse enter highlights
            li.addEventListener('mouseenter', () => this._setActive(idx, true /*noFocus*/));
            this.$list.appendChild(li);
        });

        this.$list.style.display = 'block';
        this.$input.setAttribute('aria-expanded', 'true');
        this.$input.setAttribute('aria-activedescendant', '');
        this._toggleClear();
    }

    /* ------------- keyboard handling ------------- */
    _handleKeyOnInput(e) {
        const hasMenu = this._items.length > 0;
        if (!hasMenu && e.key === 'Tab') return; // nothing to move to

        switch (e.key) {
            case 'ArrowDown':
                if (hasMenu) {
                    e.preventDefault();
                    this._focusItem(0);
                }
                break;
            case 'Tab':
                if (hasMenu && !e.shiftKey) {
                    // Move focus into the list (first item)
                    e.preventDefault();
                    this._focusItem(0);
                }
                break;
            case 'Escape':
                this._render([]);
                break;
            default:
                // no-op
                break;
        }
    }

    _handleKeyOnItem(e) {
        const li = e.target.closest('.za-item');
        if (!li) return;
        const idx = parseInt(li.getAttribute('data-idx') || '-1', 10);
        if (idx < 0) return;
        const last = this._items.length - 1;

        switch (e.key) {
            case 'ArrowDown':
                e.preventDefault();
                this._focusItem(Math.min(last, idx + 1));
                break;
            case 'ArrowUp':
                e.preventDefault();
                if (idx === 0) {
                    // back to input
                    this.$input.focus();
                    this._setActive(-1, true);
                } else {
                    this._focusItem(idx - 1);
                }
                break;
            case 'Enter':
            case ' ':
                e.preventDefault();
                this._choose(idx);
                break;
            case 'Tab':
                if (!e.shiftKey) {
                    // select on Tab forward
                    e.preventDefault();
                    this._choose(idx);
                } // Shift+Tab: allow bubbling to move focus back out
                break;
            case 'Escape':
                this._render([]);
                this.$input.focus();
                break;
            default:
                break;
        }
    }

    /* ------------- mouse handling ------------- */
    _handleClick(e) {
        const li = e.target.closest('.za-item');
        if (!li) return;
        const idx = parseInt(li.getAttribute('data-idx') || '-1', 10);
        if (idx >= 0) this._choose(idx);
    }

    /* ------------- focus/blur ------------- */
    _handleBlur(e) {
        const related = e.relatedTarget;
        if (!this.contains(related)) {
            this._render([]); // hide list when focus leaves the component
        }
    }
    _handleFocus() {
        const q = this.$input.value.trim();
        if (q.length >= this._minlen && this._items.length) {
            this.$list.style.display = 'block';
            this.$input.setAttribute('aria-expanded', 'true');
        }
        this._toggleClear();
    }

    /* ------------- clear button ------------- */
    _handleClear() {
        this.clear();
        this.$input.focus();
    }
    _toggleClear() {
        const show = !!(this.$input.value || this._selected);
        this.$clear.style.display = show ? 'block' : 'none';
    }

    /* ------------- helpers ------------- */
    _setActive(idx, noFocus = false) {
        const items = Array.from(this.$list.children);
        items.forEach(el => {
            el.style.background = '';
            el.setAttribute('aria-selected', 'false');
        });
        this._active = idx;
        if (idx >= 0 && items[idx]) {
            items[idx].style.background = 'rgba(0,0,0,.06)';
            items[idx].setAttribute('aria-selected', 'true');
            this.$input.setAttribute('aria-activedescendant', items[idx].id || '');
            if (!noFocus) items[idx].focus({ preventScroll: false });
            items[idx].scrollIntoView({ block: 'nearest' });
        } else {
            this.$input.setAttribute('aria-activedescendant', '');
        }
    }
    _focusItem(idx) {
        this._setActive(idx);
    }

    _choose(idx) {
        const item = this._items[idx];
        if (!item) return;
        this._selected = item;
        // Put a human-friendly value in the input; keep key in dataset
        this.$input.value = this._stripHtml(item.bib) || item.title || '';
        this.$input.dataset.key = item.key;
        this._render([]); // hide
        this._toggleClear(); // show the clear button

        this.dispatchEvent(
            new CustomEvent('zotero-select', {
                bubbles: true,
                detail: { key: item.key, title: item.title || '', bib: item.bib || '' },
            }),
        );
    }

    _debounce(fn, ms) {
        let t = null;
        return (...args) => {
            clearTimeout(t);
            t = setTimeout(() => fn.apply(this, args), ms);
        };
    }
    _escape(s) {
        return String(s).replace(
            /[&<>"']/g,
            ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch],
        );
    }
    _stripHtml(s) {
        const tmp = document.createElement('div');
        tmp.innerHTML = s || '';
        return tmp.textContent || '';
    }
    _uid() {
        return Math.random().toString(36).slice(2);
    }
}

customElements.define('zotero-autocomplete', ZoteroAutocomplete);
/* ==================== /ZOTERO AUTOCOMPLETE WEB COMPONENT ==================== */
