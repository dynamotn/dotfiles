class Clock extends Component {
  time = '00:00';

  template() {
    return this.time;
  }

  setTime() {
    Number.prototype.pad = function (n = 2) {
      return (Array(n).join("0") + this).substr(-n);
    };
    const date = new Date();
    this.time = date.getHours().pad() + ':' + date.getMinutes().pad();
    this.render();
  }

  connectedCallback() {
    this.render().then(() => {
      this.setTime();
    });
    setInterval(() => this.setTime(), 1000);
  }
}
