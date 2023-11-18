class Tabs extends Component {
  constructor() {
    super();
    this.tabs = LOADED_CONFIG.tabs;
  }

  style() {
    return `
      .wallpaper {
        width: 100%;
        height: 100%;
        position: absolute;
        background-image: url("src/img/background.png");
        background-repeat: round;
        background-size: cover;
      }

      .panel {
        border-radius: 5px 0 0 5px;
        width: 50%;
        height: 400px;
        right: 0;
        left: 0;
        top: 50px;
        bottom: 0;
        margin: auto;
        box-shadow: 0 5px 10px rgba(0, 0, 0, .2);
        background: #24273a;
        position: relative;
      }

      .slides {
        width: 100%;
        height: 100%;
        overflow: hidden;
        position: relative;
        border-radius: 10px 0 0 10px;
      }

      .slides ul {
        --panelbg: transparent;
        --flavour: var(--blue);
        width: 100%;
        height: 100%;
        right: 100%;
        transition: all .6s;
        position: absolute;
      }

      .slides ul[active] {
        right: 0;
        z-index: 1;
      }

      .slides .banners {
        position: absolute;
        left: 0;
        width: 30%;
        height: 100%;
        flex-wrap: wrap;
      }

      .slides .banners::after {
        content: attr(data-name);
        position: absolute;
        display: flex;
        text-transform: uppercase;
        overflow-wrap: break-word;
        width: 25px;
        height: 250px;
        padding: 1em;
        margin: auto;
        border-radius: 5px;
        box-shadow: inset 0 0 0 2px var(--flavour);
        left: 0;
        right: 0;
        bottom: 0;
        top: 0;
        background: linear-gradient(to top, rgb(50 48 47 / 90%), transparent);
        color: var(--flavour);
        letter-spacing: 1px;
        font: 500 30px 'Nunito', sans-serif;
        text-align: center;
        flex-wrap: wrap;
        word-break: break-all;
        align-items: center;
        backdrop-filter: blur(3px);
      }

      .slides ul:nth-child(2) {
        --flavour: var(--peach);
      }

      .slides ul:nth-child(3) {
        --flavour: var(--green);
      }

      .slides ul:nth-child(4) {
        --flavour: var(--red);
      }
      .slides ul:nth-child(5) {
        --flavour: var(--mauve);
      }

      .slides .links {
        position: absolute;
        box-shadow: inset -2px 0 var(--flavour);
        right: 0;
        width: 70%;
        height: 100%;
        background: var(--bg);
        padding: 5%;
        flex-wrap: wrap;
      }
    `;
  }

  template() {
    return `
      <div class="wallpaper"></div>
      <div class="panel">
        <div class="slides">
          ${Slide.getAll(this.tabs)}
        </div>
      </div>
    `;
  }
}
