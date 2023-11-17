class Tabs extends Component {
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

      .container {
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
    `;
  }

  template() {
    return `
      <div class="wallpaper"></div>
      <div class="container">
        <div class="panel">
          <h3>This is bookmarks</h3>
        </div>
      </div>
    `;
  }

  connectedCallback() {
    this.render();
  }
}
