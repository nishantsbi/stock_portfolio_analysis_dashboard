# Scripts are used within the Shiny App ----

# 1.0 Getting and Cleaning Stock Data ----
# 1.1 Function is used to get data from selected stock index ----
get_stock_data_function <- function(data,
                                    startDate, 
                                    endDate){
    
    stocks <- data$symbols %>% 
        na.omit() %>%  
        as.character() 
    
    getSymbols(stocks,
               src = "yahoo",
               from= startDate,
               to = endDate,
               auto.assign = TRUE,
               warnings = FALSE
    ) %>% 
        map(~Ad(get(.))) %>% # Gets adjusted price for each stock, but returns an xts for each stock symbol
        reduce(merge) %>%    # merges all xts into a single one, based on date column
        `colnames<-`(stocks) # change the column names to the symbol names
}

# 1.2 Calculate Returns ----
calculate_returns_function <- function(data,weights_tbl,timePeriod){
    
    data <- data
    
    if(timePeriod == "monthly"){
        data <- data %>% 
            to.monthly(indexAt = "lastof", OHLC = FALSE)
    } else if(timePeriod == "weekly"){
        data <- data %>% 
            to.weekly(indexAt = "lastof", OHLC = FALSE)
    } else {
        data <- data %>% 
            to.yearly(indexAt = "lastof", OHLC = FALSE)
    }
    
    data <- data %>% 
        data.frame(date = index(.)) %>% 
        remove_rownames() %>% 
        pivot_longer(
            cols = 1:(ncol(.)-1)
        ) %>% 
        group_by(name) %>% 
        mutate(returns = (log(value)-log(lag(value)))) %>% 
        select(-value) %>% 
        ungroup() %>% 
        na.omit() %>% 
        rename(asset = name)
        
        # Calculate Portfolio Returns
    portfolio <- data %>% 
        left_join(weights_tbl, by = c('asset' = 'symbols')) %>% 
        mutate(weighted_returns = returns * weights) %>% 
        group_by(date) %>% 
        summarize(returns = sum(weighted_returns)) %>% 
        mutate(asset = 'Portfolio')
    
    # Combine both invidual assets and portfolio into single tibble
    data <- data %>% 
        bind_rows(portfolio) %>% 
        mutate(returns_formatted = scales::percent(returns,accuracy = 0.01)) %>% 
        mutate(label_text = str_glue('Asset: {asset}
                                    Return: {returns_formatted}
                                    Date: {date}'))

    
    return(data)
}

# 2.0 Rolling Calculations ----

rolling_calculation_function <- function(data, window, .func, func_label){
    rolling_func <- rollify(.func,window = window)
    
    label_function <- func_label
    
    data %>% 
        as_tbl_time(index = date) %>% 
        mutate(value = round(rolling_func(returns),4)) %>% 
        na.omit() %>% 
        mutate(label_text = str_glue('Asset: {asset}
                                    {label_function}: {value}
                                    Date: {date}'))
}

# 3.0 Covariance and Correlation Functions ----

tidy_data_for_covar_cor_function <- function(data,marketAsset){
  
  long_data <- data %>% 
    filter(asset != marketAsset) %>% 
    filter(asset != 'Portfolio') %>% 
    select(-c(label_text,returns_formatted)) %>% 
    pivot_wider(
      names_from = asset,
      values_from = returns
    ) %>%
    select(-date)
  
  return(long_data)
}

covariance_function <- function(data){
  
  covar_matrix <- data %>% 
    cov()
  
  return(covar_matrix)
}

correlation_function <- function(data){
  correlation_matrix <- data %>% 
    cor()
  
  return(correlation_matrix)
}

matrix_to_df_function <- function(matrix){
  
  matrix_tbl <- matrix %>% 
    as.data.frame() %>% 
    rownames_to_column(var = "var1") %>% 
    pivot_longer(
      cols = 2:length(.),
      names_to = "var2"
    ) %>% 
    mutate(value = round(value,3))
  
  return(matrix_tbl)
}

# 3.0 Component Contribution Calculations ----
component_contribution_function <- function(covar_matrix,weights_tbl,marketAsset){

    weights <- weights_tbl %>% 
      
        filter(symbols != marketAsset) %>%
        select(weights) %>% 
        mutate(weights = as.numeric(as.character(weights))) %>% 
        slice(1:(n())) %>% 
        pull()
    
    sd_portfolio <- sqrt(t(weights) %*% covar_matrix %*% weights)
    
     marginal_contribution <- weights %*% covar_matrix / sd_portfolio[1,1]
     
     component_contribution <- marginal_contribution * weights
     
     component_percentages <- component_contribution/sd_portfolio[1,1]
      
     component_percentages_tbl <- component_percentages %>% 
          as_tibble() %>% 
          pivot_longer(
              cols = 1:length(.),
              names_to = 'asset',
              values_to = 'contribution'
          ) %>% 
          mutate(contribution_formatted = scales::percent(contribution,accuracy = 0.01)) %>% 
          mutate(label_text = str_glue('Asset: {asset}
                                      Contribution: {contribution_formatted}')
          )
    
    return(component_percentages_tbl)
}


# 4.0 Simulation Functions ----

