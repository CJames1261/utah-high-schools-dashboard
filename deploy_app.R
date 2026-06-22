# 1. Check what renv thinks changed
renv::status()

# 2. Update renv.lock with any new packages you used
renv::snapshot()

# 3. Confirm rsconnect sees the updated dependency list
rsconnect::appDependencies()

# 4. Deploy as a NEW shinyapps.io app
rsconnect::deployApp(
  appName = "multi-state-school-dashboard"
)
