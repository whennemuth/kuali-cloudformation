package org.bu.jenkins.job.kuali;

import java.net.URLDecoder;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;
import org.bu.jenkins.AWSCredentials;
import org.bu.jenkins.active_choices.dao.RdsInstanceDAO;
import org.bu.jenkins.active_choices.dao.RdsSnapshotDAO;
import org.bu.jenkins.active_choices.dao.StackDAO;
import org.bu.jenkins.active_choices.html.AbstractParameterView;
import org.bu.jenkins.active_choices.model.AbstractAwsResource;
import org.bu.jenkins.active_choices.model.Landscape;
import org.bu.jenkins.active_choices.model.RdsInstance;
import org.bu.jenkins.active_choices.model.RdsSnapshot;
import org.bu.jenkins.job.AbstractJob;
import org.bu.jenkins.job.JobParameter;
import org.bu.jenkins.job.JobParameterConfiguration;
import org.bu.jenkins.job.JobParameterMetadata;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.SimpleHttpHandler;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * This class is associated with the jenkins job used to create and delete application stacks for Kuali.
 * It is primarily concerned with generating the html behind all of the active choices parameters in that job.
 * All fields are rendered at the same time and so the entire job is handed back as html in one go, instead
 * of rendering a single parameter.
 * 
 * @author wrh
 *
 */
public class StackCreateDelete extends AbstractJob {
		
	private Logger logger = LogManager.getLogger(StackCreateDelete.class.getName());
	
	public StackCreateDelete(AWSCredentials credentials) {		
		this.credentials = credentials;
	}
	
	public StackCreateDelete() {
		this.credentials = AWSCredentials.getInstance();
	}

	@Override
	public boolean isPageRefresh(Map<String, String> parameters) {
		if(parameters.isEmpty()) {
			logger.info("New or refreshed page");
			return true;
		}
		for(Entry<String, String> p : parameters.entrySet()) {
			logger.debug("          {}: {}", p.getKey(), p.getValue());
		}
		return false;
	}

	@Override
	public void flushCache() {
		logger.info("Flushing cache...");
		StackDAO.CACHE.flush();
		RdsInstanceDAO.CACHE.flush();
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
		RDS_INSTANCE_BY_BASELINE("RDS", "rds-instances-by-baseline"),
		RDS_INSTANCE_BY_LANDSCAPE("RDS", "rds-instances-by-landscape"),
		RDS_SNAPSHOT("RDS", "rds-snapshot"),
		RDS_SNAPSHOT_ORPHANS("RDS", "rds-snapshot-orphans"),
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
		EntryMessage m = logger.traceEntry("getRenderedParameter(config.getParameterName()={})", config.getParameterName());
		
		try {
			AbstractParameterView parameterView = getSparseParameterView(config, "org/bu/jenkins/active_choices/html/job-parameter/");
			
			applyCustomStateToParameterView(config, parameterView);
			
			logger.traceExit(m);
			return parameterView.render();
		} 
		catch (Exception e) {
			e.printStackTrace();
			logger.traceExit(m);
			return stackTraceToHTML(e);
		}
	}

	@Override
	public void checkJobParameterConfig(JobParameterConfiguration config) {
		EntryMessage m = logger.traceEntry("checkJobParameterConfig(config.getParameterName()={})", config.getParameterName());
		String possibleAlias = config.getParameterMap().get(ParameterName.LANDSCAPE.name());
		config.setParameterMapValue(ParameterName.LANDSCAPE.name(), Landscape.idFromAlias(possibleAlias));
		logger.traceExit(m);
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
		EntryMessage m = logger.traceEntry("applyCustomStateToParameterView(config.getParameterName()={}, parameterView.getViewName()={})", config.getParameterName(), parameterView.getViewName());
		
		ParameterName parameter = ParameterName.valueOf(config.getParameterName());
		
		JobParameter jobParameter = new JobParameter(parameter, config.getParameterMap());
		if( stackSelected(jobParameter)) {
			parameterView.setContextVariable("stackSelected", true);
		}
		switch(parameter) {
			case STACK:
				logger.debug("Rendering: {}", ParameterName.STACK.name());
				StackDAO stackList = new StackDAO(credentials);
				parameterView.setContextVariable("stacks", stackList.getKualiApplicationStacks());
				break;
			case STACK_ACTION:
				logger.debug("Rendering: {}", ParameterName.STACK_ACTION.name());
				if(stackSelected(jobParameter)) {
					parameterView.setContextVariable("stackSelected", true);
				}
				else if(jobParameter.hasAnyValue("create", "recreate")) {
					jobParameter.setValue(null);
					parameterView.setContextVariable(ParameterName.STACK_ACTION.name(), null);
				}
				break;
			default:
				if(jobParameter.otherParmSetWith(ParameterName.STACK_ACTION, "delete")) {
					parameterView.setContextVariable("deactivate", true);
					parameterView.setContextVariable(ParameterName.STACK_ACTION.name(), null);
				}
				else {
					RdsInstanceDAO rdsDAO = new RdsInstanceDAO(credentials);
					RdsSnapshotDAO rdsSnapshotDAO = new RdsSnapshotDAO(credentials);
					boolean include = false;
					switch(parameter) {
						case LANDSCAPE:
							break;
						case STACK_TYPE:
							logger.debug("Rendering: {}", ParameterName.STACK_TYPE.name());
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("ParameterValue", "ecs");
								parameterView.setContextVariable("ecs_only", true);
							}
							break;
						case BASELINE: 
						case ADVANCED_KEEP_LAMBDA_LOGS: 
						case ADVANCED_MANUAL_ENTRIES:
							// These views are to be rendered as a sub view of other views view, so deactivate it here.
							logger.debug("Skipping rendering: {}", parameter.name());
							parameterView.setContextVariable("deactivate", true);
							break;
						case AUTHENTICATION:
							logger.debug("Rendering: {}", ParameterName.AUTHENTICATION.name());
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
							logger.debug("Rendering: {}", ParameterName.DNS.name());
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
							logger.debug("Rendering: {}", ParameterName.WAF.name());
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
							logger.debug("Rendering: {}", ParameterName.ALB.name());
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
							logger.debug("Rendering: {}", ParameterName.RDS_SOURCE.name());
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
						case RDS_INSTANCE_BY_LANDSCAPE:
							logger.debug("Rendering: {}", ParameterName.RDS_INSTANCE_BY_LANDSCAPE.name());
							if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "instance")) {
								List<RdsInstance> rdsInstances = new ArrayList<RdsInstance>(rdsDAO.getDeployedKualiRdsInstances());
								parameterView.setContextVariable("rdsInstances", rdsInstances);								
								parameterView.setContextVariable("ParameterValue", getRdsArnForLandscape(jobParameter));
								include = true;								
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_INSTANCE_BY_BASELINE:
							logger.debug("Rendering: {}", ParameterName.RDS_INSTANCE_BY_BASELINE.name());
							if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "owned-snapshot")) {
								Map<Landscape, List<RdsInstance>> map = rdsDAO.getDeployedKualiRdsInstancesGroupedByBaseline();
								parameterView.setContextVariable("rdsArnsByBaseline", map);
								parameterView.setContextVariable("ParameterValue",  getRdsArnForBaseline(jobParameter));
								include = true;								
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_SNAPSHOT:	
							logger.debug("Rendering: {}", ParameterName.RDS_SNAPSHOT.name());
							if(jobParameter.otherParmNotSetWith(ParameterName.LANDSCAPE, "prod") && 
									jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "owned-snapshot")) {
								String rdsArn = getRdsArnForBaseline(jobParameter);
								if(rdsArn != null) {
									AbstractAwsResource rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
									parameterView.setContextVariable("rdsInstance", rdsInstance);
									include = true;									
								}
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_SNAPSHOT_ORPHANS:
							logger.debug("Rendering: {}", ParameterName.RDS_SNAPSHOT_ORPHANS.name());
							if(jobParameter.otherParmNotSetWith(ParameterName.LANDSCAPE, "prod") && 
									jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "orphaned-snapshot")) {
//								List<RdsSnapshot> orphaned = rdsSnapshotDAO.getAllOrphanedKualiRdsSnapshots(rdsDAO);
//								parameterView.setContextVariable("orphanedSnapshots", orphaned);
								Map<Landscape, List<RdsSnapshot>> orphaned = rdsSnapshotDAO.getAllOrphanedKualiRdsSnapshotssGroupedByBaseline(rdsDAO);
								parameterView.setContextVariable("snapshotArnsByBaseline", orphaned);
								include = true;
							}
							parameterView.setContextVariable("include", include);
							break;
						case RDS_WARNING:
							logger.debug("Rendering: {}", ParameterName.RDS_WARNING.name());
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
										AbstractAwsResource rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
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
								else if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "owned-snapshot")) {
									String rdsArn = getRdsArnForBaseline(jobParameter);
									if(rdsArn != null) {
										AbstractAwsResource rdsInstance = rdsDAO.getRdsInstanceByArn(rdsArn);
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
								else if(jobParameter.otherParmSetWith(ParameterName.RDS_SOURCE, "orphaned-snapshot")) {
									
								}
							}
							parameterView.setContextVariable("rdsWarning", warning);
							parameterView.setContextVariable("include", warning != null);
							break;
						case MONGO:
							logger.debug("Rendering: {}", ParameterName.MONGO.name());
							if(jobParameter.otherParmSetWith(ParameterName.LANDSCAPE, "prod")) {
								parameterView.setContextVariable("deactivate_mongo", true);
								parameterView.setContextVariable("ParameterValue", "disabled");
							}							
							else {
								parameterView.setContextVariable("ParameterValue", jobParameter.isChecked() ? "enabled" : "disabled");
							}
							break;
						case ADVANCED:
							logger.debug("Rendering: {}", ParameterName.ADVANCED.name());
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
		logger.traceExit(m);
	}
	
	/**
	 * Get the value RDS_INSTANCES_BY_LANDSCAPE, which if null, find a default value for, selecting a one 
	 * compatible with LANDSCAPE, else the first value found.
	 */
	private String getRdsArnForLandscape(JobParameter jobParameter) {
		EntryMessage m = logger.traceEntry("getRdsArnForLandscape(jobParameter.getName()={})", jobParameter.getName());
		
		String rdsArn = jobParameter.getOtherParmValue(ParameterName.RDS_INSTANCE_BY_LANDSCAPE);
		if(rdsArn != null) {
			logger.traceExit(m);
			return rdsArn;
		}
		
		List<RdsInstance> rdsInstances = new ArrayList<RdsInstance>(
				new RdsInstanceDAO(credentials).getDeployedKualiRdsInstances());
		
		if(jobParameter.isBlank() && rdsInstances.isEmpty() == false) {
			String landscape = jobParameter.getOtherParmValue(ParameterName.LANDSCAPE);
			rdsArn = rdsInstances.get(0).getArn();
			for(AbstractAwsResource rdsInstance : rdsInstances) {
				if(landscape != null && landscape.equalsIgnoreCase(rdsInstance.getBaseline())) {
					rdsArn = rdsInstance.getArn();
				}
			}
		}
		
		logger.traceExit(m);
		return rdsArn;
	}
	
	private String getRdsArnForBaseline(JobParameter jobParameter) {
		EntryMessage m = logger.traceEntry("getRdsArnForBaseline(jobParameter.getName()={})", jobParameter.getName());
		
		String rdsArn = jobParameter.getOtherParmValue(ParameterName.RDS_INSTANCE_BY_BASELINE);
		if(rdsArn != null) {
			logger.traceExit(m);
			return rdsArn;
		}
		
		Map<Landscape, List<RdsInstance>> map = new RdsInstanceDAO(credentials).getDeployedKualiRdsInstancesGroupedByBaseline();
		
		if(jobParameter.isBlank() && map.isEmpty() == false) {
			String landscape = jobParameter.getOtherParmValue(ParameterName.LANDSCAPE);
			for(Landscape baseline : map.keySet()) {
				List<RdsInstance> rdsInstances = map.get(baseline);
				if( ! rdsInstances.isEmpty()) {
					if(rdsArn == null) {
						rdsArn = rdsInstances.get(0).getArn();
					}
					if(baseline.is(landscape)) {
						rdsArn = rdsInstances.get(0).getArn();
						break;
					}
				}
			}
		}
		
		logger.traceExit(m);
		return rdsArn;
	}
	
	private boolean stackSelected(JobParameter jobParameter) {
		return ! jobParameter.otherParmBlank(ParameterName.STACK) && 
				 jobParameter.otherParmNotSetWith(ParameterName.STACK.name(), "none");
	}

	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		AbstractJob job = new StackCreateDelete(AWSCredentials.getInstance(namedArgs));
		final String parmNameKey = "parameter-name";
		
		if(namedArgs.has(parmNameKey)) {
			// Return an html rendering of a single job parameter field.
			if(ParameterName.valueOf(namedArgs.get(parmNameKey)) == null) {
				System.out.println(String.format("No such job parameter: %s", parmNameKey));
				return;
			}
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					JobParameterConfiguration config = 
							JobParameterConfiguration.getNestedFieldInstance(namedArgs.get(parmNameKey))
							.setParameterMap(parameters);
					return job.getRenderedParameter(config);
				}}
			.setPort(namedArgs.getInt("port"))
			.visitWithBrowser(false);
		}
		else {
			new SimpleHttpHandler() {
				@Override public String getHtml(Map<String, String> parameters) {
					return job.getRenderedJob(parameters, true);
				}}
			.setPort(namedArgs.getInt("port"))
			.visitWithBrowser(true);			
		}
	}
}
