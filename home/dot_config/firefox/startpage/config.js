let saved_config = JSON.parse(localStorage.getItem("LOADED_CONFIG"));

const default_config = {
  tabs: [
    {
      name: "work",
      background_url: "src/img/tabs/work.gif",
      categories: [
        {
          name: "development",
          links: [
            {
              name: "github",
              url: "https://github.com",
              icon: " ",
              icon_color: "var(--green)",
            },
            {
              name: "gitlab",
              url: "https://gitlab.com",
              icon: " ",
              icon_color: "var(--peach)",
            },
          ],
        },
        {
          name: "email",
          links: [
            {
              name: "gmail",
              url: "https://mail.google.com",
              icon: "󰊫 ",
              icon_color: "var(--red)",
            },
          ],
        },
      ],
    },
  ],
};

const LOADED_CONFIG = new Config(saved_config ?? default_config);
