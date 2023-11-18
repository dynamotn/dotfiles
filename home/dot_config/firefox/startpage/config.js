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
              icon: "brand-github",
              icon_color: "#a6da95",
            },
          ]
        },
      ],
    },
  ],
};

const LOADED_CONFIG = new Config(saved_config ?? default_config);
