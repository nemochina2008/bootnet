# Creates the summary table
summary.bootnet <- function(
  object, # bootnet object
  statistics = c("edge", "intercept", "strength", "closeness", "betweenness","distance"), # stats to include in the table
  perNode = FALSE, # Set to true to investigate nodewise stabilty per node.
  ...
){

  # Returns quantiles for type = "observation" and correlations with original for type = "node"
  if (object$type == "observation"){
    tab <- object$bootTable %>% 
      dplyr::filter_(~type %in% statistics) %>%
      dplyr::group_by_(~type, ~node1, ~node2, ~id) %>%
      dplyr::summarize_(
        mean = ~mean(value),
        var = ~var(value),
        sd = ~sd(value),
        prop0 = ~mean(value == 0),
        q1 = ~quantile(value,1/100, na.rm = TRUE),
        q2.5 = ~quantile(value, 2.5/100, na.rm = TRUE),
        q5 = ~quantile(value, 5/100, na.rm = TRUE),
        q25 = ~quantile(value, 25/100, na.rm = TRUE),
        q50 = ~quantile(value, 50/100, na.rm = TRUE),
        q75 = ~quantile(value, 75/100, na.rm = TRUE),
        q95 = ~quantile(value, 95/100, na.rm = TRUE),
        q97.5 = ~quantile(value, 97.5/100, na.rm = TRUE),
        q99 = ~quantile(value, 99/100, na.rm = TRUE)
      ) %>%
      dplyr::left_join(object$sampleTable %>% dplyr::select_(~type,~id,~node1,~node2,sample = ~value), by=c("id","type","node1","node2")) %>%
      dplyr::select_(~type, ~id, ~node1, ~node2, ~sample, ~mean, ~var, ~q1, ~q2.5, ~q5, ~q25, ~q50, ~q75, ~q95, ~q97.5, ~q99)
    
  } else {
    # Nodewise
    tab <- object$bootTable %>% 
      dplyr::filter_(~type %in% statistics) %>% 
      dplyr::left_join(object$sampleTable %>% dplyr::select_(~type,~id,~node1,~node2,sample = ~value), by=c("id","type","node1","node2"))
    
    if (perNode){
      tab <- tab %>% group_by_(~id, ~type, ~nNode)  %>%
        dplyr::summarize_(
          mean = ~mean(value),
          var = ~var(value),
          sd = ~sd(value),
          q1 = ~quantile(value,1/100, na.rm = TRUE),
          q2.5 = ~quantile(value, 2.5/100, na.rm = TRUE),
          q5 = ~quantile(value, 5/100, na.rm = TRUE),
          q25 = ~quantile(value, 25/100, na.rm = TRUE),
          q50 = ~quantile(value, 50/100, na.rm = TRUE),
          q75 = ~quantile(value, 75/100, na.rm = TRUE),
          q95 = ~quantile(value, 95/100, na.rm = TRUE),
          q97.5 = ~quantile(value, 97.5/100, na.rm = TRUE),
          q99 = ~quantile(value, 99/100, na.rm = TRUE)
        ) %>% arrange_(~nNode)
      
    } else {
      tab <- tab %>% group_by_(~name, ~type, ~nNode)  %>%
        summarize_(cor = ~cor(value,sample, use = "pairwise.complete.obs")) %>%
        dplyr::group_by_(~nNode, ~type) %>%
        dplyr::summarize_(
          mean = ~mean(cor),
          var = ~var(cor),
          sd = ~sd(cor),
          q1 = ~quantile(cor,1/100, na.rm = TRUE),
          q2.5 = ~quantile(cor, 2.5/100, na.rm = TRUE),
          q5 = ~quantile(cor, 5/100, na.rm = TRUE),
          q25 = ~quantile(cor, 25/100, na.rm = TRUE),
          q50 = ~quantile(cor, 50/100, na.rm = TRUE),
          q75 = ~quantile(cor, 75/100, na.rm = TRUE),
          q95 = ~quantile(cor, 95/100, na.rm = TRUE),
          q97.5 = ~quantile(cor, 97.5/100, na.rm = TRUE),
          q99 = ~quantile(cor, 99/100, na.rm = TRUE)
        ) %>% arrange_(~nNode)
      
    }
  }
  
  
  return(tab)
}

