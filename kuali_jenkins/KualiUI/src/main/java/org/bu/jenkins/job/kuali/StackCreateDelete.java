package org.bu.jenkins.job.kuali;

import java.net.URLDecoder;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.NamedArgs;
import org.bu.jenkins.SimpleHttpHandler;
import org.bu.jenkins.active_choices.dao.LandscapeDAO;
import org.bu.jenkins.active_choices.dao.RdsDAO;
import org.bu.jenkins.active_choices.html.AbstractParameterView;
import org.bu.jenkins.active_choices.model.Landscape;
import org.bu.jenkins.active_choices.model.RdsInstance;
import org.bu.jenkins.active_choices.model.StackList;
import org.bu.jenkins.job.AbstractJob;
import org.bu.jenkins.job.JobParameter;
import org.bu.jenkins.job.JobParameterConfiguration;
import org.bu.jenkins.job.JobParameterMetadata;

/**
 * This class is associated with the jenkins job used to create and delete application stacks for Kuali.
 * It is primarily concerned with generating the html behind any of the active choices parameters in that job.
 * 
 * @author wrh
 *
 */
public class StackCreateDelete extends AbstractJob {
	
	
	public StackCreateDelete(AWSCredentials credentials) {		
		this.credentials = credentials;
	}
	
	public StackCreateDelete() {
		this.credentials = new AWSCredentials();
	}
	
	public static enum ParameterName implements JobParameterMetadata {
		STACK("StackListTable", "stack-list-table"),
		STACK_ACTION("StackAction", "stack-action"),
		STACK_TYPE("StackType", "stack-type"),
		BASELINE("Baseline", "baseline"),
		LANDSCAPE("Landscape", "landscape"),
		AUTHENTICATION("Authentication", "authentication"),
		DNS("DNS", "dns"),
		WAF("WAF", "waf"),
		ALB("ALB", "alb"),
		RDS_SOURCE("RDS", "rds-source"),
		RDS_INSTANCES_BY_BASELINE("RDS", "rds-instances-by-baseline"),
		RDS_INSTANCES_BY_LANDSCAPE("RDS", "rds-instances-by-landscape"),
		RDS_SNAPSHOT("RDS", "rds-snapshot"),
		RDS_WARNING("RDS", "rds-warning"),
		MONGO("Mongo", "mongo"),
		ADVANCED("Advanced", "advanced"),
		ADVANCED_KEEP_LAMBDA_LOGS("AdvancedKeepLambdaLogs", "advancedKeepLambdaLogs"),
		ADVANCED_MANUAL_ENTRIES("AdvancedManualEntries", "advancedManualEntries");
		
		private String viewName;
		private String templateSelector;
		
		ParameterName(String viewName, String templateSelector) {
			this.viewName = viewName;
			this.templateSelector = templateSelector;
		}
		@Override
		public String getViewName() {
			return viewName;
		}
		@Override
		public String getTemplateSelector() {
			return templateSelector;
		}		
	}

	@Override
	public JobParameterMetadata[] getJobParameterMetadata() {
		return ParameterName.values();
	}

	@Override
	public String getJobName() {
		return this.getClass().getName();
	}

	@Override
	public String getRenderedParameter(JobParameterConfiguration config) {		
		try {
			AbstractParameterView parameterView = getSparseParameterView(config, "org/bu/jenkins/active_choices/html/job-parameter/");
			
			applyCustomStateToParameterView(config, parameterView);
			
			return parameterView.render();
		} 
		catch (Exception e) {
			e.printStackTrace();
			return stackTraceToHTML(e);
		}
	}

	@Override
	public void checkJobParameterConfig(JobParameterConfiguration config) {
		String possibleAlias = config.getParameterMap().get(ParameterName.LANDSCAPE.name());
		config.setParameterMapValue(ParameterName.LANDSCAPE.name(), Landscape.idFromAlias(possibleAlias));
	}
	
	/**
	 * This is where we "decide", based on the value of other parameters, what a parameter should offer for choices
	 * and whether or not it should be enabled/visible at all. This is done by loading the view context with the 
	 * appropriate values/objects.
	 * @param config
	 * @param parameterView
	 */
	@SuppressWarnings("incomplete-switch")
	private void applyCustomStateToParameterView(JobParameterConfiguration config, AbstractParameterView parameterView) throws Exception {
		
		ParameterName parameter = ParameterName.valueOf(config.getParameterName());
		
		JobParameter jobParameter = new JobParameter(parameter, config.getParameterMap());
		if( ! jobParameter.otherParmBlank(ParameterName.STACK)) {
			parameterView.setContextVariable("stackSelected", true);
		}
		switch(parameter) {
			case STACK:
				StackList stackList = new StackList(credentials);
				parameterView.setContextVariable("stacks", stackList.getKualiApplicationStacks());
				break;
			case STACK_ACTION:
				if( ! jobParameter.otherParmBlank(ParameterName.STACK)) {
					parameterView.setContextVariable("stackSelected", true);
				}
				break;
			default:
				if( ! jobParameter.otherParmSetWith(ParameterName.STACK_ACTION, "create")) {
					parameterView.setContextVariable("deactivate", true);
				}
				else {
					RdsDAO rdsDAO = new RdsDAO(credentials);
					boolean include = false;
					switch(parameter) {
						case LANDSCAPE:
							break;
						case STACK_TYPE:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "ecs");
								parameterView.setContextVariable("ecs_only", true);
							}
							break;
						case BASELINE: 
						case ADVANCED_KEEP_LAMBDA_LOGS: 
						case ADVANCED_MANUAL_ENTRIES:
							// These views are to be rendered as a sub view of other views view, so deactivate it here.
							parameterView.setContextVariable("deactivate", true);
							break;
						case AUTHENTICATION:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "shibboleth");
								parameterView.setContextVariable("deactivate_cor_main", true);
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2") || 
									jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "sb")) {
								parameterView.setContextVariable("ParameterValue", "cor-main");
								parameterView.setContextVariable("deactivate_shibboleth", true);
							}
							break;
						case DNS:							
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "route53");
								parameterView.setContextVariable("deactivate_none", true);
							}							
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("ParameterValue", "none");
								parameterView.setContextVariable("deactivate_route53", true);
							}
							else if(jobParameter.otherParmSetWith(ParameterName.AUTHENTICATION, "shibboleth")) {
								parameterView.setContextVariable("ParameterValue", "route53");
								if( ! jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "sb")) {
									parameterView.setContextVariable("deactivate_none", true);
								}
							}							
							break;
						case WAF:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_waf", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("deactivate_waf", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}
							else {
								parameterView.setContextVariable("ParameterValue", jobParameter.isChecked() ? "enabled" : "disabled");
							}
							break;
						case ALB:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.STACK_TYPE, "ec2")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}
							else if(jobParameter.otherParmSetWith(ParameterName.WAF, "enabled")) {
								parameterView.setContextVariable("deactivate_alb", true);
								parameterView.setContextVariable("ParameterValue", "enabled");
							}
							else {
								parameterView.setContextVariable("ParameterValue", jobParameter.isChecked() ? "enabled" : "disabled");
							}
							break;
						case RDS_SOURCE:							
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_landscape", true);
								parameterView.setContextVariable("ParameterValue", "instance");
								parameterView.setContextVariable("instance_only", true);
							}
							else {
								parameterView.setContextVariable("rdsInstances", rdsDAO.getDeployedKualiRdsInstances());
								String urlEncodedValue = config.getParameterMap().get(parameter.name());
								if(urlEncodedValue != null) {
									String urlDecodedValue = URLDecoder.decode(urlEncodedValue, Charset.defaultCharset());
									parameterView.setContextVariable("ParameterValue", urlDecodedValue);
								}								
							}
							break;
						case RDS_INSTANCES_BY_LANDSCAPE:
							if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "instance")) {
								List<RdsInstance> rdsInstances = new ArrayList<RdsInstance>(rdsDAO.getDeployedKualiRdsInstances());
								parameterView.setContextVariable("rdsInstances", rdsInstances);								
								parameterView.setContextVariable("ParameterValue", getRdsArnForLandscape(jobParameter));
								include = true;								
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_INSTANCES_BY_BASELINE:
							if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "snapshot")) {
								Map<String, List<RdsInstance>> map = rdsDAO.getDeployedKualiRdsInstancesGroupedByBaseline();
								parameterView.setContextVariable("rdsArnsByBaseline", map);
								parameterView.setContextVariable("ParameterValue",  getRdsArnForBaseline(jobParameter));
								include = true;								
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_SNAPSHOT:	
							if(jobParameter.otherParmNotSetWith(ParameterName.LANDSCAPE, "prod") && 
									jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "snapshot")) {
								String rdsArn = getRdsArnForBaseline(jobParameter);
								if(rdsArn != null) {
									RdsInstance rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
									parameterView.setContextVariable("rdsInstance", rdsInstance);
									include = true;									
								}
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_WARNING:
							String landscape = jobParameter.getOtherParmValue(ParameterName.LANDSCAPE);
							String warning = null;
							if(Landscape.fromAlias(landscape) != null) {
								String template = "You seem to have selected a baseline landscape for the entire stack (\"%s\"). "
										+ "However, you have also opted to %s based "
										+ "on a different baseline landscape (\"%s\"). "
										+ "Among other potential incompatibilities, kc-config.xml will contain a password "
										+ "for the KCOEUS user that won't work until you perform an update to the KCOEUS user, "
										+ "changing the password to the one that secrets manager has for \"%s\". Recommend selecting an "
										+ "rds instance with a matching baseline landscape instead.";

								if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "instance")) {
									String rdsArn = getRdsArnForLandscape(jobParameter);
									if(rdsArn != null) {
										RdsInstance rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
										if( ! landscape.equalsIgnoreCase(rdsInstance.getBaseline())) {
											warning = String.format(
													template, 
													landscape,
													"use an existing rds instance",
													rdsInstance.getBaseline(),
													rdsInstance.getBaseline());
										}
									}
								}
								else if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "snapshot")) {
									String rdsArn = getRdsArnForBaseline(jobParameter);
									if(rdsArn != null) {
										RdsInstance rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
										if( ! landscape.equalsIgnoreCase(rdsInstance.getBaseline())) {
											warning = String.format(
													template, 
													landscape,
													"create an rds instance from a snapshot",
													rdsInstance.getBaseline(),
													rdsInstance.getBaseline());
										}
									}
								}
							}
							parameterView.setContextVariable("rdsWarning", warning);
							parameterView.setContextVariable("include", warning != null);
							break;
						case MONGO:
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_mongo", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}							
							else {
								parameterView.setContextVariable("ParameterValue", jobParameter.isChecked() ? "enabled" : "disabled");
							}
							break;
						case ADVANCED:
							parameterView.setContextVariable("ParameterValue", jobParameter.isChecked() ? "enabled" : "disabled");
							parameterView.setContextVariable("ksbrlEnum", ParameterName.ADVANCED_KEEP_LAMBDA_LOGS);
							parameterView.setContextVariable("ksbrlValue", jobParameter.isChecked(ParameterName.ADVANCED_KEEP_LAMBDA_LOGS) ? "enabled" : "disabled");
							parameterView.setContextVariable("manualEnum", ParameterName.ADVANCED_MANUAL_ENTRIES);
							String urlEncodedValue = config.getParameterMap().get(ParameterName.ADVANCED_MANUAL_ENTRIES.name());
							if(urlEncodedValue != null) {
								String urlDecodedValue = URLDecoder.decode(urlEncodedValue, Charset.defaultCharset());
								parameterView.setContextVariable("manualValue", urlDecodedValue);
							}
							break;
					}					
				}
		}
		
	}
	
	/**
	 * Get the value RDS_INSTANCES_BY_LANDSCAPE, which if null, find a default value for, selecting a one 
	 * compatible with LANDSCAPE, else the first value found.
	 */
	private String getRdsArnForLandscape(JobParameter jobParameter) {
		
		String rdsArn = jobParameter.getOtherParmValue(ParameterName.RDS_INSTANCES_BY_LANDSCAPE);
		if(rdsArn != null) {
			return rdsArn;
		}
		
		List<RdsInstance> rdsInstances = new ArrayList<RdsInstance>(
				new RdsDAO(credentials).getDeployedKualiRdsInstances());
		
		if(jobParameter.isBlank() && rdsInstances.isEmpty() == false) {
			String landscape = jobParameter.getOtherParmValue(ParameterName.LANDSCAPE);
			rdsArn = rdsInstances.get(0).getArn();
			if(landscape != null) {	
				for(RdsInstance rdsInstance : rdsInstances) {
					if(landscape.equalsIgnoreCase(rdsInstance.getBaseline())) {
						rdsArn = rdsInstance.getArn();
					}
				}
			}
		}
		
		return rdsArn;
	}
	
	private String getRdsArnForBaseline(JobParameter jobParameter) {
		
		String rdsArn = jobParameter.getOtherParmValue(ParameterName.RDS_INSTANCES_BY_BASELINE);
		if(rdsArn != null) {
			return rdsArn;
		}
		
		Map<String, List<RdsInstance>> map = new RdsDAO(credentials).getDeployedKualiRdsInstancesGroupedByBaseline();
		
		if(jobParameter.isBlank() && map.isEmpty() == false) {
			String landscape = jobParameter.getOtherParmValue(ParameterName.LANDSCAPE);
			if(landscape != null) {	
				for(String baseline : map.keySet()) {
					List<RdsInstance> rdsInstances = map.get(baseline);
					if( ! rdsInstances.isEmpty()) {
						if(rdsArn == null) {
							rdsArn = rdsInstances.get(0).getArn();
						}
						if(baseline.equalsIgnoreCase(landscape)) {
							rdsArn = rdsInstances.get(0).getArn();
							break;
						}
					}
				}
			}
		}
		
		return rdsArn;
	}

	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(args);
		AbstractJob job = new StackCreateDelete(new AWSCredentials(namedArgs));
		
		if(namedArgs.has("parameter-name")) {
			if(ParameterName.valueOf(namedArgs.get("parameter-name")) == null) {
				System.out.println("No such parameter name!");
				return;
			}
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					JobParameterConfiguration config = 
							JobParameterConfiguration.forTestFragmentInstance(namedArgs.get("ParameterName"))
							.setParameterMap(parameters);
					return job.getRenderedParameter(config);
				}}.visitWithBrowser(false);
		}
		else {
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					return job.getRenderedJob(parameters, true);
				}}.visitWithBrowser(true);			
		}
	}
}
