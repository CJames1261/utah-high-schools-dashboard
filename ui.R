# ui.R

fluidPage(
  titlePanel("Utah Public High Schools — U.S. News 2025-2026"),

  sidebarLayout(
    sidebarPanel(
      width = 3,

      selectInput(
        "district", "School District:",
        choices  = c("All districts", sort(unique(schools$district))),
        selected = "All districts"
      ),

      selectInput(
        "school", "School:",
        choices  = c("All schools", sort(unique(schools$school_name))),
        selected = "All schools"
      ),

      actionButton("reset_view", "Reset map view", width = "100%"),

      hr(),
      h4("Average scorecard"),
      uiOutput("avg_scorecard"),

      hr(),
      h4("Selected school"),
      uiOutput("school_stats"),

      hr(),
      tags$small(
        sprintf("Data: %d schools across %d districts (U.S. News Best High Schools 2025-2026). ",
                nrow(schools), length(unique(schools$district))),
        "Coordinates from the Geocodio CSV; district polygons from Census TIGER. ",
        tags$a(href = "https://www.usnews.com/education/best-high-schools/utah/rankings",
               target = "_blank", "Rankings source ↗")
      )
    ),

    mainPanel(
      width = 9,
      leafletOutput("map", height = "85vh")
    )
  )
)
