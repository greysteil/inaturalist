import _ from "lodash";
import React, { PropTypes } from "react";



class ResearchGradeProgress extends React.Component {

  constructor( ) {
    super( );
    this.criteriaList = this.criteriaList.bind( this );
  }

  outlinkIcon( source ) {
    switch ( source ) {
      case "Atlas of Living Australia":
        return "/assets/sites/ala.png";
      case "Calflora":
        return "/assets/sites/calflora.png";
      case "GBIF":
        return "/assets/sites/gbif.png";
      case "GloBI":
        return "/assets/sites/globi.png";
      default:
        return null;
    }
  }

  criteriaList( ) {
    const { observation, qualityMetrics } = this.props;
    let remainingCriteria = { };
    const passedCriteria = { };
    remainingCriteria.date = !observation.observed_on;
    remainingCriteria.media = ( observation.photos.length + observation.sounds.length ) === 0;
    remainingCriteria.rank = ( observation.taxon && observation.taxon.rank_level > 10 );
    remainingCriteria.ids = !observation.identifications_most_agree;
    remainingCriteria.location = !observation.location;
    const votesFor = { };
    const votesAgainst = { };
    _.each( qualityMetrics, ( values, metric ) => {
      _.each( values, v => {
        const agree = ( "vote_scope" in v ) ? !v.vote_flag : v.agree;
        if ( agree ) {
          votesFor[metric] = votesFor[metric] || 0;
          votesFor[metric] += 1;
        } else {
          votesAgainst[metric] = votesAgainst[metric] || 0;
          votesAgainst[metric] += 1;
        }
      } );
    } );
    _.each( qualityMetrics, ( values, metric ) => {
      const score = ( votesFor[metric] || 0 ) - ( votesAgainst[metric] || 0 );
      if ( score < 0 ) {
        remainingCriteria[`metric-${metric}`] = true;
      } else if ( score > 0 ) {
        passedCriteria[`metric-${metric}`] = true;
      }
    } );
    remainingCriteria.flags = observation.flags.length > 0;
    if ( observation.taxon && observation.taxon.rank_level === 20 ) {
      remainingCriteria.rank = false;
      if ( !passedCriteria["metric-needs_id"] ) {
        remainingCriteria["metric-needs_id"] = false;
        remainingCriteria.rank_or_needs_id = true;
      }
    }
    remainingCriteria = _.pickBy( remainingCriteria, bool => ( bool === true ) );
    return (
      <ul className="remaining">
        { _.map( remainingCriteria, ( bool, type ) => {
          if ( type === "rank_or_needs_id" ) {
            return (
              <li
                key="need-rank_or_needs_id"
                className={ _.size( remainingCriteria ) > 1 ? "top_border" : "" }
              >
                <div className="reason">
                  <div className="reason_icon">
                    <i className="fa fa-leaf" />
                  </div>
                  <div className="reason_label">
                    { I18n.t( "community_id_at_species_level_or_lower" ) }
                  </div>
                </div>
                <div className="or">
                  - { I18n.t( "or" ) } -
                </div>
                <div className="reason">
                  <div className="reason_icon">
                    <i className="fa fa-gavel" />
                  </div>
                  <div className="reason_label">
                    { I18n.t( "the_community_must_feel_that" ) }
                  </div>
                </div>
              </li>
            );
          }
          let icon;
          let label;
          switch ( type ) {
            case "date":
              icon = "fa-calendar";
              label = I18n.t( "date_specified" );
              break;
            case "location":
              icon = "fa-map-marker";
              label = I18n.t( "location_specified" );
              break;
            case "media":
              icon = "fa-file-image-o";
              label = I18n.t( "has_photos_or_sounds" );
              break;
            case "ids":
              icon = "icon-identification";
              label = I18n.t( "has_id_supported_by_two_or_more" );
              break;
            case "rank":
              icon = "fa-leaf";
              label = I18n.t( "community_id_at_species_level_or_lower" );
              break;
            case "metric-date":
              icon = "fa-calendar-check-o";
              label = I18n.t( "date_is_accurate" );
              break;
            case "metric-location":
              icon = "fa-bullseye";
              label = I18n.t( "location_is_accurate" );
              break;
            case "metric-wild":
              icon = "fa-bolt";
              label = I18n.t( "organism_is_wild" );
              break;
            case "metric-evidence":
              icon = "fa-bolt";
              label = I18n.t( "evidence_of_organism" );
              break;
            case "metric-recent":
              icon = "fa-bolt";
              label = I18n.t( "recent_evidence_of_organism" );
              break;
            case "metric-needs_id":
              icon = "fa-gavel";
              label = I18n.t( "the_community_must_feel_that" );
              break;
            case "flags":
              icon = "fa-flag danger";
              label = I18n.t( "all_flags_must_be_resolved" );
              break;
            default:
              return null;
          }
          return (
            <li key={ `need-${type}` }>
              <div className="reason_icon">
                <i className={ `fa ${icon}` } />
              </div>
              <div className="reason_label">{ label }</div>
            </li>
          );
        } ) }
      </ul>
    );
  }

  render( ) {
    const observation = this.props.observation;
    if ( !observation ) { return ( <div /> ); }
    const grade = observation.quality_grade;
    const needsIDActive = ( grade === "needs_id" || grade === "research" );
    let description;
    let criteria;
    let outlinks;
    if ( grade === "research" ) {
      description = (
        <span>
          <span className="bold">{ I18n.t( "this_observation_is_research_grade" ) }</span>
          { I18n.t( "it_can_now_be_used_for_research" ) }.
        </span>
      );
    } else {
      criteria = this.criteriaList( );
      description = (
        <span
          dangerouslySetInnerHTML={ { __html: I18n.t( "the_below_items_are_needed_to_achieve" ) } }
        />
      );
    }
    if ( observation.outlinks && observation.outlinks.length > 0 ) {
      outlinks = ( <div className="outlinks">
        <span className="intro">
          { I18n.t( "this_observation_is_featured_on_x_sites", {
            count: observation.outlinks.length } ) }
          { grade !== "research" ? (
            <span className="intro-sub">
              { I18n.t( "please_allow_a_few_weeks_for_external_sites" ) }
            </span>
          ) : "" }
        </span>
        { observation.outlinks.map( ol => (
          <div className="outlink" key={ `outlink-${ol.source}` }>
            <a href={ ol.url }>
              <div className="squareIcon">
                <img src={ this.outlinkIcon( ol.source ) } />
              </div>
              <div className="title">{ ol.source }</div>
            </a>
          </div>
        ) ) }
      </div> );
    }
    return (
      <div className="ResearchGradeProgress">
        <div className="graphic">
          <div className="checks">
            <div className="check active">
              <i className="fa fa-check" />
            </div>
            <div className={ `separator ${needsIDActive ? "active" : "incomplete"}` } />
            <div className={ `check needs-id ${needsIDActive ? "active" : "incomplete"}` }>
              <i className="fa fa-check" />
            </div>
            <div className={ `separator ${grade === "research" ? "active" : "incomplete"}` } />
            <div className={ `check research ${grade === "research" ? "active" : "incomplete"}` }>
              <i className="fa fa-check" />
            </div>
          </div>
          <div className="labels">
            <div className={ `casual ${grade === "casual" && "active"}` }>Casual Grade</div>
            <div className={ `needs-id ${grade === "needs_id" && "active"}` }>Needs ID</div>
            <div className={ `research ${grade === "research" && "active"}` }>Research Grade</div>
          </div>
        </div>
        <div className="info">
          { description }
        </div>
        { criteria }
        { outlinks }
      </div>
    );
  }
}

ResearchGradeProgress.propTypes = {
  observation: PropTypes.object,
  qualityMetrics: PropTypes.object
};

export default ResearchGradeProgress;
