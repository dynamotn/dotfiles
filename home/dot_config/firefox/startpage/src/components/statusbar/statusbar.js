class Statusbar extends Component {
  externalRefs = {};

  refs = {
    slides: ".slides ul",
    tabs: ".tabs ul li",
    indicator: ".indicator",
  };

  currentTabIndex = 0;

  constructor() {
    super();

    this.setDependencies();
  }

  setDependencies() {
    this.externalRefs = {
      slides: this.parentNode.querySelectorAll(this.refs.slides),
    };
  }

  imports() {
    return [
      '<link rel="stylesheet" type="text/css" href="src/css/statusbar.css">',
    ];
  }

  style() {
    var style = '';
    LOADED_CONFIG.tabs.forEach((tab) => {
      if (tab.tab_color) {
        style += `
          .tabs ul li[active]:nth-child(${LOADED_CONFIG.tabs.indexOf(tab) + 1}) ~ li:last-child {
            margin: 0 0 0 ${LOADED_CONFIG.tabs.indexOf(tab) * 35}px;
          }
          .tabs ul li[active]:nth-child(${LOADED_CONFIG.tabs.indexOf(tab) + 1})  ~ li:last-child {
            --flavour: var(--${tab.tab_color});
          }
        `;
      }
    });
    return style;
  }

  template() {
    return `
      <div class="tabs">
        <cols>
          <ul class="indicator"></ul>
        </cols>
      </div>`;
  }

  setEvents() {
    this.refs.tabs.forEach((tab) => (tab.onclick = ({ target }) => this.handleTabChange(target)));

    document.onkeydown = (e) => this.handleKeyPress(e);
    document.onwheel = (e) => this.handleWheelScroll(e);

    if (LOADED_CONFIG.openLastVisitedTab) {
      window.onbeforeunload = () => this.saveCurrentTab();
    }
  }

  saveCurrentTab() {
    localStorage.lastVisitedTab = this.currentTabIndex;
  }

  openLastVisitedTab() {
    if (!LOADED_CONFIG.openLastVisitedTab) return;
    this.activateByKey(localStorage.lastVisitedTab);
  }

  handleTabChange(tab) {
    this.activateByKey(Number(tab.getAttribute("tab-index")));
  }

  handleWheelScroll(event) {
    if (!event) return;

    let { target, wheelDelta } = event;

    if (target.shadow && target.shadow.activeElement) return;

    let activeTab = -1;
    this.refs.tabs.forEach((tab, index) => {
      if (tab.getAttribute("active") === "") {
        activeTab = index;
      }
    });

    if (wheelDelta > 0) {
      this.activateByKey((activeTab + 1) % (this.refs.tabs.length - 1));
    } else {
      this.activateByKey(activeTab - 1 < 0 ? this.refs.tabs.length - 2 : activeTab - 1);
    }
  }

  handleKeyPress(event) {
    if (!event) return;

    let { target, key } = event;

    if (target.shadow && target.shadow.activeElement) return;

    if (Number.isInteger(parseInt(key)) && key <= this.externalRefs.slides.length) {
      this.activateByKey(key - 1);
    }
  }

  activateByKey(key) {
    if (key < 0) return;
    this.currentTabIndex = key;

    this.activate(this.refs.tabs, this.refs.tabs[key]);
    this.activate(this.externalRefs.slides, this.externalRefs.slides[key]);
  }

  createTabs() {
    const slidesCount = this.externalRefs.slides.length;

    for (let i = 0; i <= slidesCount; i++) {
      this.refs.indicator.innerHTML += `<li tab-index=${i} ${i == 0 ? "active" : ""}></li>`;
    }
  }

  activate(target, item) {
    target.forEach((i) => i.removeAttribute("active"));
    item.setAttribute("active", "");
  }

  connectedCallback() {
    this.render().then(() => {
      this.createTabs();
      this.setEvents();
      this.openLastVisitedTab();
    });
  }
}
